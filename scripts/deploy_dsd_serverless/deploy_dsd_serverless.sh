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

# Función para verificar archivo DSD
check_dsd_file() {

    if ! cd src; then
        log_error "No se puede cambiar al directorio src"
        exit 1
    fi

    # Buscar archivo DSD
    local dsd_file
    dsd_file=$(ls .dsd_*.yml 2>/dev/null || true)

    if [[ -z "$dsd_file" ]]; then
        log_error "No se encontró un archivo '.dsd_serverless'"
        log_info "Ejecuta primero 'make generate_stack_dsd'"
        exit 1
    fi

    # Verificar que solo hay un archivo
    local file_count
    file_count=$(echo "$dsd_file" | wc -l)
    if [[ $file_count -gt 1 ]]; then
        log_error "Se encontraron múltiples archivos DSD:"
        echo "$dsd_file"
        log_info "Por favor elimina los archivos duplicados"
        exit 1
    fi

    echo "$dsd_file"
}

# Función para verificar estado del stack
check_stack_status() {
    cd src
    local dsd_file="$1"

    log_info "Verificando estado del stack..."

    local output
    if ! output=$(sls info --stage dev -c "$dsd_file" 2>&1); then
        if echo "$output" | grep -q "does not exist"; then
            log_info "Stack no existe, procediendo con deploy..."
            return 0
        else
            log_error "Error al verificar estado del stack"
            log_error "Detalles: \n $output"
            return 1
        fi
    fi

    log_success "Stack existe y está activo"
    return 0
}

# Función para realizar deploy
perform_deploy() {
    local dsd_file="$1"

    log_info "Iniciando deploy del stack..."

    # Crear archivo temporal para capturar salida
    local output_file
    output_file=$(mktemp)

    # Función de limpieza
    cleanup() {
        if [[ -n "${output_file:-}" ]]; then
            rm -f "$output_file"
        fi
    }

    # Configurar trap para limpieza
    trap cleanup EXIT

    # Ejecutar deploy con captura de salida
    log_info "Ejecutando 'sls deploy --verbose --stage dev -c $dsd_file'"

    if ! sls deploy --verbose --stage dev -c "$dsd_file" 2>&1 | tee "$output_file"; then
        log_error "Error durante el deploy del stack"

        # Extraer información del error
        log_error "Detalles del error:"
        log_error "-------------------"
        if [[ -f "$output_file" ]]; then
            grep -A 10 -i "Error:" "$output_file" || true
            grep -A 5 -i "Failed:" "$output_file" || true
        fi

        # Aplicar rollback
        log_warning "Aplicando rollback..."
        cd ..
        if ! make dsd_rm; then
            log_error "Error durante el rollback"
            log_info "Por favor ejecuta manualmente: make dsd_rm"
        else
            log_success "Rollback completado"
            exit 0
        fi

        exit 1
    fi

    log_success "Deploy completado exitosamente"
}

# Función para mostrar información del usuario
show_user_info() {
    log_info "Obteniendo información del usuario..."

    local user_dsd
    # Ejecutar desde paquete instalado
    local package_dir
    package_dir=$(dirname "$(dirname "$(readlink -f "$0")")")
    if ! user_dsd=$("$package_dir/genera_dsd_serverless/nombre_usuario.sh"); then
        log_warning "No se pudo obtener información del usuario"
        return
    fi

    # Validar respuesta
    case "$user_dsd" in
        "U"|"T"|"")
            log_warning "Usuario no válido: $user_dsd"
            return
            ;;
        *)
            log_success "Deploy completado para usuario: $user_dsd"
            echo ""
            echo "============================================="
            echo "=                                           ="
            echo "=     Tu id de gitlab es $user_dsd"
            echo "=                                           ="
            echo "=     El sufijo que se utilizará para dsd... ="
            echo "=             dsd-$user_dsd"
            echo "=                                           ="
            echo "============================================="
            echo ""
            ;;
    esac
}

# Función para mostrar recursos modificados
show_modified_resources() {
    local archivo_nombres="./src/.dsd_nombres_modificados.txt"

    if [[ -f "$archivo_nombres" ]]; then
        log_info "Mostrando recursos modificados por límite de caracteres..."

        echo ""
        echo "A los siguientes recursos o funciones se les cambió la stage develop por dev..."
        echo "debido a que el nombre excedía los 64 caracteres."
        echo ""
        echo "**********************************************"
        if [[ -s "$archivo_nombres" ]]; then
            cat "$archivo_nombres"
        else
            echo "No se encontraron recursos modificados"
        fi
        echo "**********************************************"
        echo ""

        # Limpiar archivo
        rm -f "$archivo_nombres"
        log_success "Archivo de nombres modificados limpiado"
    fi
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

    # Verificar make
    if ! command -v make &> /dev/null; then
        log_error "Make no está instalado"
        exit 1
    fi

    log_success "Todas las dependencias están disponibles"
}

# Función principal
main() {
    echo ""
    echo "+----------------------+"
    echo "|                      |"
    echo "|Desplegando stack...  |"
    echo "|                      |"
    echo "+----------------------+"
    echo ""

    # Verificar dependencias
    check_dependencies

    # Verificar archivo DSD
    local dsd_file
    dsd_file=$(check_dsd_file)

    # Verificar estado del stack
    if ! check_stack_status "$dsd_file"; then
        exit 1
    fi

    # Realizar deploy
    if ! perform_deploy "$dsd_file"; then
        exit 1
    fi

    # Regresar al directorio raíz
    cd ..

    # Mostrar información del usuario
    show_user_info

    # Mostrar recursos modificados
    show_modified_resources

    log_success "Proceso de deploy completado exitosamente"
}

# Ejecutar función principal
main "$@"
