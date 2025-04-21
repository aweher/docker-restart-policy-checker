#!/bin/bash
# Script para verificar políticas de reinicio en Docker - Optimizado para ejecución remota
# Uso: curl -L script.pages.dev | bash
#   o: curl -L script.pages.dev | bash -s -- --json (para formato JSON)

# Establecer opciones de salida (tabla por defecto, json como opción)
OUTPUT_FORMAT="table"
[ "$1" = "--json" ] && OUTPUT_FORMAT="json"

# Función para salida JSON
output_json() {
    # Imprimir objeto JSON
    echo "{"
    echo "  \"host\": \"$(hostname)\","
    echo "  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
    echo "  \"docker_installed\": $1,"
    
    if [ "$1" = "true" ]; then
        echo "  \"containers\": ["
        i=0
        while IFS="|" read -r name restart_policy status image; do
            [ $i -gt 0 ] && echo "    ,"
            echo "    {"
            echo "      \"name\": \"$name\","
            echo "      \"restart_policy\": \"$restart_policy\","
            echo "      \"status\": \"$status\","
            echo "      \"image\": \"$image\""
            echo -n "    }"
            i=$((i+1))
        done < "$CONTAINERS_FILE"
        echo ""
        echo "  ],"

        echo "  \"services_without_restart\": ["
        i=0
        if [ -s "$MISSING_FILE" ]; then
            while IFS=':' read -r service file container_name; do
                [ $i -gt 0 ] && echo "    ,"
                echo "    {"
                echo "      \"service\": \"$service\","
                echo "      \"file\": \"$file\","
                echo "      \"container\": \"$container_name\""
                echo -n "    }"
                i=$((i+1))
            done < "$MISSING_FILE"
        fi
        echo ""
        echo "  ]"
    fi
    echo "}"
}

# Función para salida en tabla
output_table() {
    echo "=== Docker Restart Policy Report ==="
    echo "Host: $(hostname)"
    echo "Date: $(date)"
    echo "Docker Installed: $1"
    
    if [ "$1" = "true" ]; then
        echo ""
        echo "--- Contenedores sin política de reinicio ---"
        while IFS="|" read -r name restart_policy status image; do
            if [ "$restart_policy" = "no" ] || [ -z "$restart_policy" ]; then
                echo "❌ $name (imagen: $image)"
                echo "   Estado: $status"
                echo "   Política: $restart_policy"
            fi
        done < "$CONTAINERS_FILE"
        
        echo ""
        echo "--- Servicios caídos sin política de reinicio ---"
        if [ -s "$MISSING_FILE" ]; then
            while IFS=':' read -r service file container_name; do
                echo "🔴 Servicio: $service"
                echo "   Contenedor: $container_name"
                echo "   Archivo: $file"
            done < "$MISSING_FILE"
        else
            echo "No se encontraron servicios caídos sin política de reinicio"
        fi
    fi
}

# Verificar que Docker está instalado
if ! command -v docker &> /dev/null; then
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        output_json "false"
    else
        output_table "false"
    fi
    exit 0
fi

# Crear archivos temporales
TEMP_DIR=$(mktemp -d)
CONTAINERS_FILE="$TEMP_DIR/containers.txt"
SERVICES_FILE="$TEMP_DIR/services.txt"
MISSING_FILE="$TEMP_DIR/missing_services.txt"

# Función de limpieza para eliminar archivos temporales al salir
cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null
}
trap cleanup EXIT

# Recolectar información de contenedores
while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    restart=$(echo "$line" | awk '{print $2}')
    status=$(docker ps -a -f "name=$name" --format "{{.Status}}" 2>/dev/null)
    image=$(docker ps -a -f "name=$name" --format "{{.Image}}" 2>/dev/null)
    echo "$name|$restart|$status|$image" >> "$CONTAINERS_FILE"
done < <(docker ps -a --format "{{.Names}} {{.RestartPolicy}}" 2>/dev/null)

# Encontrar todos los docker-compose y sus servicios definidos
COMPOSE_FILES=$(find / -type f -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null)

if [ -n "$COMPOSE_FILES" ] && docker compose version &> /dev/null; then
    for file in $COMPOSE_FILES; do
        dir=$(dirname "$file")
        filename=$(basename "$file")
        cd "$dir" || continue
        
        SERVICES=$(docker compose -f "$filename" config --services 2>/dev/null)
        if [ -z "$SERVICES" ]; then
            continue
        fi
        
        for service in $SERVICES; do
            restart_policy=$(docker compose -f "$filename" config 2>/dev/null | grep -A 20 "  $service:" | grep "restart:" | head -1 | awk '{print $2}')
            
            service_container=$(echo "$service" | tr '[:upper:]' '[:lower:]')
            project_name=$(basename "$dir" | tr '[:upper:]' '[:lower:]')
            
            # Posibles nombres de contenedor
            possible_names=(
                "${project_name}_${service_container}_1"
                "${project_name}-${service_container}-1"
                "${dir##*/}_${service_container}_1"
                "${dir##*/}-${service_container}-1"
                "$service_container"
                "${project_name}-${service_container}"
            )
            
            for name in "${possible_names[@]}"; do
                container_exists=false
                container_running=false
                
                status=$(docker ps -a -f "name=$name" --format "{{.Status}}" 2>/dev/null)
                if [ -n "$status" ]; then
                    container_exists=true
                    [[ $status == Up* ]] && container_running=true
                    
                    if [ -z "$restart_policy" ] && [ "$container_exists" = true ] && [ "$container_running" = false ]; then
                        echo "$service:$file:$name" >> "$MISSING_FILE"
                    fi
                    break
                fi
            done
        done
        cd - > /dev/null || true
    done
fi

# Generar la salida en el formato solicitado
if [ "$OUTPUT_FORMAT" = "json" ]; then
    output_json "true"
else
    output_table "true"
fi

exit 0