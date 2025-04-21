#!/bin/bash
# Script para verificar políticas de reinicio en Docker - Optimizado para ejecución remota
# Uso: curl -L script.pages.dev | bash
#   o: curl -L script.pages.dev | bash -s -- --json (para formato JSON)
#   o: curl -L script.pages.dev | bash -s -- --silent (sin barra de progreso)

# Establecer opciones
OUTPUT_FORMAT="table"
SHOW_PROGRESS=true

# Procesar argumentos
for arg in "$@"; do
  case $arg in
    --json)
      OUTPUT_FORMAT="json"
      ;;
    --silent)
      SHOW_PROGRESS=false
      ;;
  esac
done

# Función para mostrar barra de progreso
show_progress() {
  if [ "$SHOW_PROGRESS" = true ]; then
    local msg="$1"
    local progress="$2"
    local total="$3"
    local percent=$((progress * 100 / total))
    local completed=$((percent / 2))
    local remaining=$((50 - completed))
    
    # Construir la barra de progreso
    local bar="["
    for ((i=0; i<completed; i++)); do bar+="="; done
    if [ $completed -lt 50 ]; then bar+=">"; fi
    for ((i=0; i<remaining-1; i++)); do bar+=" "; done
    bar+="] $percent%"
    
    # Mostrar la barra
    printf "\r%-30s %s" "$msg" "$bar"
    if [ "$progress" -eq "$total" ]; then
      printf "\n"
    fi
  fi
}

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
        local found=false
        while IFS="|" read -r name restart_policy status image; do
            if [ "$restart_policy" = "no" ] || [ -z "$restart_policy" ]; then
                echo "❌ $name (imagen: $image)"
                echo "   Estado: $status"
                echo "   Política: $restart_policy"
                found=true
            fi
        done < "$CONTAINERS_FILE"
        
        [ "$found" = false ] && echo "No se encontraron contenedores sin política de reinicio"
        
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

# Mostrar mensaje de inicio
if [ "$SHOW_PROGRESS" = true ]; then
    echo "Verificando políticas de reinicio Docker en $(hostname)..."
fi

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

# Iniciar la barra de progreso
show_progress "Analizando contenedores" 0 5

# Recolectar información de contenedores
while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    restart=$(echo "$line" | awk '{print $2}')
    status=$(docker ps -a -f "name=$name" --format "{{.Status}}" 2>/dev/null)
    image=$(docker ps -a -f "name=$name" --format "{{.Image}}" 2>/dev/null)
    echo "$name|$restart|$status|$image" >> "$CONTAINERS_FILE"
done < <(docker ps -a --format "{{.Names}} {{.RestartPolicy}}" 2>/dev/null)

show_progress "Buscando docker-compose" 1 5

# Encontrar todos los docker-compose en el sistema
COMPOSE_FILES=$(find / -type f -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null)

show_progress "Analizando servicios" 2 5

# Contador para controlar el progreso
total_files=$(echo "$COMPOSE_FILES" | wc -l)
current_file=0

if [ -n "$COMPOSE_FILES" ] && docker compose version &> /dev/null; then
    for file in $COMPOSE_FILES; do
        current_file=$((current_file + 1))
        progress=$((2 + current_file * 2 / total_files))
        show_progress "Analizando archivos compose" $progress 5
        
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

show_progress "Preparando informe" 4 5

# Generar la salida en el formato solicitado
if [ "$OUTPUT_FORMAT" = "json" ]; then
    show_progress "Generando JSON" 5 5
    output_json "true"
else
    show_progress "Generando informe" 5 5
    output_table "true"
fi

exit 0