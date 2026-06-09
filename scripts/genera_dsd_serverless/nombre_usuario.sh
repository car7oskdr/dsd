#!/bin/bash

# Configuración de errores
set -euo pipefail
trap 'echo "Error en línea $LINENO. Comando: $BASH_COMMAND"' ERR

# Colores para output
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Función para logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Función para verificar archivo .env
check_env_file() {
    if [[ ! -f ".env" ]]; then
        log_error "Archivo .env no encontrado"
        log_info "Crea el archivo .env con las variables necesarias:"
        log_info "GITLAB_TOKEN=tu_token"
        log_info "URL_GITLAB_API=https://gitlab.com/api/v4/user"
        echo "T"
        exit 1
    fi
}

# Función para cargar variables de entorno
load_env_variables() {    
    # Verificar si .env es legible
    if [[ ! -r ".env" ]]; then
        log_error "Archivo .env no es legible"
        echo "T"
        exit 1
    fi

    # Cargar variables de entorno
    if ! source .env; then
        log_error "Error al cargar archivo .env"
        echo "T"
        exit 1
    fi
}

# Función para verificar variables requeridas
check_required_variables() {    
    # Verificar GITLAB_TOKEN
    if [[ -z "${GITLAB_TOKEN:-}" ]]; then
        log_error "Variable GITLAB_TOKEN no definida en .env"
        echo "T"
        exit 1
    fi

    # Verificar URL_GITLAB_API
    if [[ -z "${URL_GITLAB_API:-}" ]]; then
        log_error "Variable URL_GITLAB_API no definida en .env"
        echo "T"
        exit 1
    fi

    # Validar formato de URL
    if [[ ! "$URL_GITLAB_API" =~ ^https?:// ]]; then
        log_error "URL_GITLAB_API no tiene un formato válido: $URL_GITLAB_API"
        echo "T"
        exit 1
    fi
}

# Función para verificar dependencias
check_dependencies() {

    # Verificar curl
    if ! command -v curl &> /dev/null; then
        log_error "curl no está instalado o no está en PATH"
        echo "T"
        exit 1
    fi

    # Verificar grep
    if ! command -v grep &> /dev/null; then
        log_error "grep no está instalado o no está en PATH"
        echo "T"
        exit 1
    fi

    # Verificar sed
    if ! command -v sed &> /dev/null; then
        log_error "sed no está instalado o no está en PATH"
        echo "T"
        exit 1
    fi
}

# Función para hacer la petición a GitLab
make_gitlab_request() {
    # Crear archivo temporal para la respuesta
    local temp_file=""
    temp_file=$(mktemp)

    # Función de limpieza
    cleanup() {
        if [[ -n "${temp_file:-}" ]]; then
            rm -f "$temp_file"
        fi
    }

    # Configurar trap para limpieza
    trap cleanup EXIT

    # Hacer petición a GitLab
    local http_code
    local response

    if ! response=$(curl --silent --show-error --write-out "%{http_code}" \
                        --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                        --output "$temp_file" \
                        "$URL_GITLAB_API" 2>&1); then
        log_error "Error al hacer petición a GitLab API"
        log_error "Detalles: $response"
        echo "U"
        exit 1
    fi

    # Extraer código HTTP
    http_code="${response: -3}"

    # Verificar código de respuesta
    if [[ "$http_code" != "200" ]]; then
        log_error "Error HTTP $http_code al hacer petición a GitLab API"
        if [[ -f "$temp_file" ]]; then
            log_error "Respuesta: $(cat "$temp_file")"
            echo "U"
            exit 1
        fi
    fi

    # Verificar que el archivo de respuesta existe y no está vacío
    if [[ ! -f "$temp_file" ]] || [[ ! -s "$temp_file" ]]; then
        log_error "Respuesta vacía de GitLab API"
        echo "U"
        exit 1
    fi

    # Copiar respuesta a user.json
    cp "$temp_file" "user.json"
    
}

# Función para extraer ID de usuario
extract_user_id() {
    # Verificar que user.json existe
    if [[ ! -f "user.json" ]]; then
        log_error "Archivo user.json no encontrado"
        echo "U"
        exit 1
    fi

    # Verificar que user.json no está vacío
    if [[ ! -s "user.json" ]]; then
        log_error "Archivo user.json está vacío"
        echo "U"
        exit 1
    fi

    # Extraer ID de usuario
    local usuario
    if ! usuario=$(grep -E '"id":[[:space:]]*[0-9]+' "user.json" | sed 's/.*"id":[[:space:]]*\([0-9]*\).*/\1/'); then
        log_error "Error al extraer ID de usuario del JSON"
        echo "U"
        exit 1
    fi

    # Verificar que se extrajo un ID válido
    if [[ -z "$usuario" ]]; then
        log_error "No se pudo extraer ID de usuario del JSON"
        cat "user.json" >&2
        echo "U"
        exit 1
    fi

    # Verificar que es un número
    if [[ ! "$usuario" =~ ^[0-9]+$ ]]; then
        log_error "ID de usuario no es un número válido: $usuario"
        echo "U"
        exit 1
    fi
    echo "$usuario"
}

# Función para limpiar archivos temporales
cleanup_temp_files() {
    if [[ -f "user.json" ]]; then
        rm -f "user.json"
    fi
}

# Función principal
main() {
    # Verificar archivo .env
    check_env_file

    # Verificar dependencias
    check_dependencies

    # Cargar variables de entorno
    load_env_variables

    # Verificar variables requeridas
    check_required_variables

    # Hacer petición a GitLab
    make_gitlab_request

    # Extraer ID de usuario
    local usuario
    usuario=$(extract_user_id)

    # Limpiar archivos temporales
    cleanup_temp_files

    # Retornar usuario
    echo "$usuario"
}

# Ejecutar función principal
main "$@"
