# Docker Restart Policy Checker

A lightweight utility script that scans your system for Docker containers and services that lack proper restart policies, helping you ensure high availability of your containerized applications.

## Overview

This script analyzes all Docker containers and docker-compose services on your system to identify:

1. Containers running without restart policies
2. Stopped containers that lack restart policies
3. Docker Compose services with missing restart configurations

## Usage

### Quick Run (No Installation)

```bash
curl -L https://restartpolicy-check.arreg.la | bash
```

### Options

Run with JSON output:

```bash
curl -L https://restartpolicy-check.arreg.la | bash -s -- --json
```

Run without progress bar (silent mode):

```bash
curl -L https://restartpolicy-check.arreg.la | bash -s -- --silent
```

Combine options:

```bash
curl -L https://restartpolicy-check.arreg.la | bash -s -- --json --silent
```

## Features

- **System-wide scan**: Finds all Docker containers and docker-compose files
- **Detailed reporting**: Shows container status, image, and restart policy
- **Multiple output formats**: Human-readable table or structured JSON
- **Progress visualization**: Real-time progress bar during analysis
- **Low overhead**: Minimal dependencies, works on any system with bash and Docker
- **Remote execution**: Run directly from URL without installation

## Output Examples

### Table Format (Default)

```txt
=== Docker Restart Policy Report ===
Host: server-name
Date: Mon Jan 1 12:00:00 UTC 2023
Docker Installed: true

--- Contenedores sin política de reinicio ---
❌ web-app (imagen: nginx:latest)
   Estado: Exited (0) 2 hours ago
   Política: no

--- Servicios caídos sin política de reinicio ---
🔴 Servicio: database
   Contenedor: project_database_1
   Archivo: /path/to/docker-compose.yml
```

### JSON Format

```json
{
  "host": "server-name",
  "timestamp": "2023-01-01T12:00:00Z",
  "docker_installed": true,
  "containers": [
    {
      "name": "web-app",
      "restart_policy": "no",
      "status": "Exited (0) 2 hours ago",
      "image": "nginx:latest"
    }
  ],
  "services_without_restart": [
    {
      "service": "database",
      "file": "/path/to/docker-compose.yml",
      "container": "project_database_1"
    }
  ]
}
```

## Why Restart Policies Matter

Docker restart policies ensure your containers automatically recover from:

- System reboots
- Container crashes
- Resource exhaustion
- Other unexpected failures

Without proper restart policies, your services may remain down after failures until manual intervention.

## Recommended Restart Policies

- `always`: Restart the container regardless of the exit status
- `unless-stopped`: Restart the container unless it was explicitly stopped
- `on-failure[:max-retries]`: Restart only if the container exits with a non-zero status

## How It Works

The script performs the following operations:

1. Checks if Docker is installed
2. Lists all running and stopped containers
3. Finds all docker-compose files in the system
4. Analyzes each service's restart policy configuration
5. Identifies containers and services without proper restart policies
6. Generates a report in the requested format

## Requirements

- Bash shell
- Docker installed
- Sufficient permissions to read docker-compose files

## License

MIT License
