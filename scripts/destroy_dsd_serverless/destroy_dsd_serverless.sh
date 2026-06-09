#!/bin/bash

# Configuración de errores
set -euo pipefail
trap 'echo "Error en línea $LINENO. Comando: $BASH_COMMAND"' ERR

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Función para logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Función para verificar credenciales AWS
check_aws_credentials() {
    log_info "Verificando credenciales de AWS..."
    cd src
    # Verificar variables de entorno AWS
    if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] || [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        log_warning "Variables AWS_ACCESS_KEY_ID o AWS_SECRET_ACCESS_KEY no están definidas"
        log_info "Verificando archivo de credenciales..."
    fi

    # Verificar credenciales directamente con AWS (sin depender de archivos serverless ni stacks)
    local output
    if ! output=$(aws sts get-caller-identity 2>&1); then
        log_error "Error al comunicarse con AWS"
        log_error "Detalles: $output"
        log_info "Por favor, exporta tus credenciales de la stage develop de AWS:"
        log_info "export AWS_ACCESS_KEY_ID=tu_access_key"
        log_info "export AWS_SECRET_ACCESS_KEY=tu_secret_key"
        log_info "export AWS_DEFAULT_REGION=tu_region"
        exit 1
    fi

    log_success "Credenciales de AWS verificadas correctamente"
}

# Función para verificar archivo DSD
check_dsd_file() {
    shopt -s nullglob
    local files=(.dsd_*.yml)
    shopt -u nullglob

    if (( ${#files[@]} == 0 )); then
        log_warning "No hay archivo DSD que destruir. Proceso completado."
        exit 0
    fi

    if (( ${#files[@]} > 1 )); then
        log_error "Se encontraron múltiples archivos DSD:"
        printf '%s\n' "${files[@]}"
        log_info "Por favor elimina los archivos duplicados manualmente"
        exit 1
    fi

    echo "${files[0]}"
}

# Función para verificar estado del stack
check_stack_status() {
    local dsd_file="$1"
    log_info "Verificando estado del stack..."

    local output
    if ! output=$(sls info --stage dev -c "$dsd_file" 2>&1); then
        if echo "$output" | grep -q "does not exist\|Stack with id"; then
            log_warning "Stack no existe o ya fue eliminado"
            log_info "Eliminando archivo local: $dsd_file"
            rm -f "$dsd_file"
            log_success "Archivo local eliminado"
            return 0
        else
            log_error "Error inesperado al verificar estado del stack"
            log_error "Detalles: $output"
            return 1
        fi
    fi

    log_success "Stack existe y está activo"
    return 0
}

# Función para destruir stack
destroy_stack() {
    local dsd_file="$1"

    log_info "Iniciando destrucción del stack..."

    # Crear archivo temporal para capturar salida
    local output_file
    output_file=$(mktemp)

    # Función de limpieza
    cleanup() {
        if [[ -f "${output_file:-}" ]]; then
            rm -f "$output_file"
        fi
    }

    # Configurar trap para limpieza
    trap cleanup EXIT

    # Ejecutar remove con captura de salida
    log_info "Ejecutando 'sls remove --verbose --stage dev -c $dsd_file'"

    if ! sls remove --verbose --stage dev -c "$dsd_file" 2>&1 | tee "$output_file"; then
        log_error "Error durante la destrucción del stack"

        # Extraer información del error
        log_error "Detalles del error:"
        log_error "-------------------"
        if [[ -f "$output_file" ]]; then
            grep -A 10 -i "Error:" "$output_file" || true
            grep -A 5 -i "Failed:" "$output_file" || true
        fi

        # Intentar eliminar archivo local de todas formas
        log_warning "Intentando eliminar archivo local..."
        rm -f "$dsd_file"

        exit 1
    fi

    log_success "Stack destruido exitosamente"
}

# Función para limpiar archivos locales
cleanup_local_files() {
    local dsd_file="$1"

    log_info "Limpiando archivos locales..."

    # Eliminar archivo DSD
    if [[ -f "$dsd_file" ]]; then
        rm -f "$dsd_file"
        log_success "Archivo DSD eliminado: $dsd_file"
    fi

    # Eliminar archivos temporales si existen
    local temp_files=(
        ".dsd-serverless.yml"
        ".resources.txt"
        ".dsd_nombres_modificados.txt"
    )

    for temp_file in "${temp_files[@]}"; do
        if [[ -f "$temp_file" ]]; then
            rm -f "$temp_file"
            log_info "Archivo temporal eliminado: $temp_file"
        fi
    done
}

# Función para verificar dependencias
check_dependencies() {
    log_info "Verificando dependencias..."

    # Verificar serverless framework
    if ! command -v sls &> /dev/null; then
        log_error "Serverless Framework no está instalado"
        log_info "Instala con: npm install -g serverless"
        exit 1
    fi

    # Verificar aws CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI no está instalado o no está en PATH"
        log_info "Instala con: pip install awscli"
        exit 1
    fi

    log_success "Todas las dependencias están disponibles"
}

# Función principal
main() {
    echo ""
    echo "+-----------------------------+"
    echo "|                             |"
    echo "|     Destruyendo stack...    |"
    echo "|                             |"
    echo "+-----------------------------+"
    echo ""

    # Verificar dependencias
    check_dependencies

    # Verificar credenciales AWS
    check_aws_credentials

    # Verificar archivo DSD
    local dsd_file
    dsd_file=$(check_dsd_file)

    # Verificar estado del stack
    if ! check_stack_status "$dsd_file"; then
        exit 1
    fi

    # Si el stack no existe, solo limpiar archivos locales
    if [[ ! -f "$dsd_file" ]]; then
        log_success "Proceso completado (stack ya no existía)"
        exit 0
    fi

    # Destruir stack
    if ! destroy_stack "$dsd_file"; then
        exit 1
    fi

    # Limpiar archivos locales
    cleanup_local_files "$dsd_file"

    log_success "Proceso de destrucción completado exitosamente"

    local shared_file=$(ls .dsd-*-shared-serverless.yml 2>/dev/null | head -n 1)

    if [[ -n "$shared_file" && -f "$shared_file" ]]; then
        log_info "Detectado $shared_file. Iniciando destrucción del stack compartido..."
        sls remove --stage dev -c "$shared_file"
        rm -f "$shared_file"
        log_success "Stack compartido destruido exitosamente"
    fi

    exit 0
}

# Ejecutar función principal
main "$@"
