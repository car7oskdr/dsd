#!/bin/bash

# Configuración de errores
set -euo pipefail  # Exit on error, undefined vars, pipe failures
trap 'echo "Error en línea $LINENO. Comando: $BASH_COMMAND"' ERR

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Función para verificar dependencias
check_dependencies() {
    log_info "Verificando dependencias..."

    # Verificar si sls está instalado
    if ! command -v sls &> /dev/null; then
        log_error "Serverless Framework no está instalado o no está en PATH"
        log_info "Instala con: npm install -g serverless"
        exit 1
    fi

    # Verificar si python está disponible
    if ! command -v python &> /dev/null; then
        log_error "Python no está instalado o no está en PATH"
        exit 1
    fi

    # Verificar si curl está disponible
    if ! command -v curl &> /dev/null; then
        log_error "curl no está instalado o no está en PATH"
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

# Función para verificar credenciales AWS
check_aws_credentials() {
    log_info "Comprobando credenciales de AWS..."

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

# Función para obtener usuario de GitLab
get_gitlab_user() {

    # Cargar variables de entorno
    if ! source .env; then
        log_error "Error al cargar archivo .env"
        exit 1
    fi

    # Verificar GITLAB_TOKEN
    if [[ -z "${GITLAB_TOKEN:-}" ]]; then
        log_error "Variable GITLAB_TOKEN no definida en .env"
        exit 1
    fi

    # Verificar URL_GITLAB_API
    if [[ -z "${URL_GITLAB_API:-}" ]]; then
        log_error "Variable URL_GITLAB_API no definida en .env"
        exit 1
    fi

    # Obtener usuario
    local user_dsd
    local package_dir
    package_dir=$(dirname "$(dirname "$(readlink -f "$0")")")
    if ! user_dsd=$("$package_dir/genera_dsd_serverless/nombre_usuario.sh"); then
        log_error "Error al ejecutar nombre_usuario.sh"
        exit 1
    fi

    # Validar respuesta
    case "$user_dsd" in
        "U")
            log_error "Error al obtener el usuario de GitLab"
            log_info "Verifica que el token sea correcto"
            log_info "Revisa el archivo user.json en la raíz"
            exit 1
            ;;
        "T")
            log_error "Variable GITLAB_TOKEN no definida"
            exit 1
            ;;
        "")
            log_error "Usuario vacío recibido de GitLab"
            exit 1
            ;;
        *)
            echo "$user_dsd"
            ;;
    esac
}

# Función para contar archivos DSD
count_dsd_files() {
    local count
    count=$(find . -maxdepth 1 -name ".dsd*serverless*.yml" 2>/dev/null | wc -l)
    echo "$count"
}

# Función para generar archivo DSD
generate_dsd_file() {
    local archivo_serverless="$1"
    local user_dsd="$2"

    log_info "Generando archivo serverless DSD..."

    # Verificar que el archivo seleccionado existe
    if [[ ! -f "$archivo_serverless" ]]; then
        log_error "Archivo $archivo_serverless no encontrado"
        exit 1
    fi

    # Los scripts están en el directorio del paquete instalado
    local package_dir
    package_dir=$(dirname "$(dirname "$(readlink -f "$0")")")
    if ! "$package_dir/recursos/recursos_stack.sh"; then
        log_error "Error ejecutando recursos_stack.sh"
        exit 1
    fi

    if ! "$package_dir/genera_dsd_serverless/genera_dsd-serverless.sh" "$archivo_serverless" "$user_dsd"; then
        log_error "Error ejecutando genera_dsd-serverless.sh"
        exit 1
    fi

    # Activar entorno virtual y ejecutar Python
    if [[ -d ".venv" ]]; then
        log_info "Activando entorno virtual..."
        if ! source .venv/bin/activate; then
            log_error "Error activando entorno virtual"
            exit 1
        fi
    else
        log_warning "Entorno virtual .venv no encontrado"
    fi

    # Ejecutar script Python
    log_info "Ejecutando procesador Python..."
    # Ejecutar desde paquete instalado
    local package_dir
    package_dir=$(dirname "$(dirname "$(readlink -f "$0")")")
    if ! python "$package_dir/genera_dsd_serverless/dsd_serverless.py" "$archivo_serverless" "$user_dsd"; then
        log_error "Error ejecutando dsd_serverless.py"
        exit 1
    fi

    # Limpiar archivos temporales
    log_info "Limpiando archivos temporales..."
    rm -f "src/.dsd-serverless.yml"
    rm -f "src/.dsd-shared-serverless.yml"
    rm -f "src/.resources.txt"
    rm -f "src/.dsd-cp-serverless.yml"
    rm -f "src/.dsd-service-serverless.yml"

    log_success "Archivo DSD generado correctamente"
}

# Función para regenerar archivo DSD
regenerate_dsd_file() {
    local archivo_serverless="$1"
    local user_dsd="$2"
    local expected_file=".dsd_${user_dsd}_${archivo_serverless}"
    local existing_file

    # Obtener archivo existente
    existing_file=$(find . -maxdepth 1 -name ".dsd_*_serverless.yaml" 2>/dev/null | head -n1)

    if [[ "$existing_file" == "./$expected_file" ]]; then
        log_info "Regenerando archivo $expected_file..."

        # Ejecutar desde paquete instalado
        local package_dir
        package_dir=$(dirname "$(dirname "$(readlink -f "$0")")")

        if ! "$package_dir/genera_dsd_serverless/genera_dsd-serverless.sh" "$archivo_serverless"; then
            log_error "Error ejecutando genera_dsd-serverless.sh"
            exit 1
        fi

        # Activar entorno virtual y ejecutar Python
        if [[ -d ".venv" ]]; then
            if ! source .venv/bin/activate; then
                log_error "Error activando entorno virtual"
                exit 1
            fi
        fi

        # Ejecutar desde paquete instalado
        local package_dir
        package_dir=$(dirname "$(dirname "$(readlink -f "$0")")")
        if ! python "$package_dir/genera_dsd_serverless/dsd_serverless.py" "$archivo_serverless" "$user_dsd"; then
            log_error "Error ejecutando dsd_serverless.py"
            exit 1
        fi

        rm -f ".dsd-serverless.yml"
        log_success "Archivo DSD regenerado correctamente"
    else
        log_error "Se encontraron múltiples archivos serverless para despliegue DSD"
        log_info "Archivo existente: $existing_file"
        log_info "Archivo esperado: $expected_file"
        log_info "Por favor elimina el stack para poder generar uno nuevo"
        log_info "Ejecuta 'make dsd_rm' para eliminar el stack"
        exit 1
    fi
}

# Función para detectar el directorio de trabajo
detect_work_directory() {
    # Si estamos en un directorio que contiene infra/ o src/, usar ese directorio
    if [[ -d "infra" ]] || [[ -d "src" ]]; then
        log_info "Directorio de trabajo detectado: $(pwd)"
        return 0
    fi
    
    # Si estamos en infra/ o src/, subir un nivel
    if [[ -d "../infra" ]] || [[ -d "../src" ]]; then
        cd ..
        log_info "Directorio de trabajo detectado: $(pwd)"
        return 0
    fi
    
    # Buscar directorio con infra/ o src/ en el directorio padre
    if [[ -d "../../infra" ]] || [[ -d "../../src" ]]; then
        cd ../..
        log_info "Directorio de trabajo detectado: $(pwd)"
        return 0
    fi
    
    log_error "No se puede detectar el directorio de trabajo"
    log_info "Asegúrate de ejecutar desde el directorio raíz del proyecto"
    return 1
}

# Función para obtener el directorio del proyecto cuando se ejecuta desde paquete instalado
get_project_directory() {
    # Si estamos en un paquete instalado, buscar el directorio del proyecto

    # Buscar en el directorio actual y directorios padre
    local current_dir="$PWD"
    local search_depth=0
    local max_depth=5

    while [[ $search_depth -lt $max_depth ]]; do
        if [[ -f "$current_dir/.env" ]] && ([[ -d "$current_dir/infra" ]] || [[ -d "$current_dir/src" ]]); then
            log_info "Proyecto encontrado en: $current_dir"
            cd "$current_dir"
            return 0
        fi
        
        # Subir un nivel
        current_dir=$(dirname "$current_dir")
        search_depth=$((search_depth + 1))
        
        # Si llegamos a la raíz, parar
        if [[ "$current_dir" == "/" ]]; then
            break
        fi
    done
    
    log_error "No se pudo encontrar el directorio del proyecto"
    log_info "Asegúrate de ejecutar desde el directorio raíz del proyecto o tener un archivo .env en el directorio raíz"
    return 1
}

# Función principal
main() {
    local version
    # Intentar obtener versión del paquete instalado
    if python -c "from importlib.metadata import version; print(version('dsd-framework'))" &> /dev/null; then
        version=$(python -c "from importlib.metadata import version; print(version('dsd-framework'))")
    else
        # Fallback: Intentar leer pyproject.toml relativo al script (modo desarrollo)
        local package_dir_script
        package_dir_script=$(dirname "$(dirname "$(readlink -f "$0")")")
        local tool_root
        tool_root=$(dirname "$(dirname "$package_dir_script")")

        if [[ -f "$tool_root/pyproject.toml" ]]; then
            version=$(grep -m 1 'version =' "$tool_root/pyproject.toml" | cut -d '"' -f 2)
        else
            version="unknown"
        fi
    fi

    echo ""
    echo "                          +---------------------------------------+"
    echo "                          |   ██████╗     ███████╗    ██████╗     |"
    echo "                          |   ██╔══██╗    ██╔════╝    ██╔══██╗    |"
    echo "                          |   ██║  ██║    ███████╗    ██║  ██║    |"
    echo "                          |   ██║  ██║    ╚════██║    ██║  ██║    |"
    echo "                          |   ██████╔╝    ███████║    ██████╔╝    |"
    echo "                          |   ╚═════╝     ╚══════╝    ╚═════╝     |"
    echo "                          |         Deploy Stack Develop          |"
    echo "                          |                v${version}                 |"
    echo "                          +---------------------------------------+"
    echo ""

    # Detectar si estamos ejecutando desde paquete instalado
    if ! get_project_directory; then
        exit 1
    fi
    
    # Detectar directorio de trabajo
    if ! detect_work_directory; then
        exit 1
    fi

    # Verificar si .env existe
    if [[ ! -f ".env" ]]; then
        log_error "Archivo .env no encontrado"
        log_info "Crea el archivo .env con las variables necesarias"
        exit 1
    fi

    # Cambiar al directorio src
    if ! cd src; then
        log_error "No se puede cambiar al directorio src"
        exit 1
    fi

    # Verificar dependencias
    check_dependencies

    # Verificar credenciales AWS
    check_aws_credentials

    # Contar archivos DSD existentes
    local dsd_file_count
    dsd_file_count=$(count_dsd_files)
    log_info "Archivos DSD serverless encontrados: $dsd_file_count"
    # Regresar al directorio raíz
    cd ..

    # Obtener usuario de GitLab
    local user_dsd
    user_dsd=$(get_gitlab_user)

    # Función para desplegar stack compartido
    deploy_shared_stack() {
        local user_dsd="$1"
        local package_dir="$2"
        local shared_file="./infra/shared/serverless.yml"

        log_info "Detectado stack de grupos. Verificando infra/shared..."

        if [[ -f "$shared_file" ]]; then
            log_info "Desplegando stack compartido primero..."

            # Generar DSD para shared
            generate_dsd_file "$shared_file" "$user_dsd"
            cd src
            # Ejecutar deploy de shared
            sls deploy --stage dev -c ".dsd-$user_dsd-shared-serverless.yml"
            cd ..
            log_success "Stack compartido desplegado. Continuando con stack seleccionado..."
        else
            log_warning "No se encontró $shared_file, continuando..."
        fi
    }

    # Procesar según el número de archivos
    case "$dsd_file_count" in
        0)
            log_info "No se encontraron archivos DSD, generando nuevo archivo..."

            # Seleccionar archivo serverless
            local archivo_serverless
            local package_dir
            package_dir=$(dirname "$(dirname "$(readlink -f "$0")")")
            if ! archivo_serverless=$("$package_dir/genera_dsd_serverless/seleccionar_archivo.sh"); then
                log_error "Error al seleccionar archivo"
                exit 1
            fi

            # Verificar si la selección fue válida
            if echo "$archivo_serverless" | grep -q "Selección"; then
                log_error "Selección fuera de rango"
                log_info "Vuelve a intentarlo..."
                exit 1
            fi

            # Verificar dependencia de shared
            if [[ "$archivo_serverless" == *"infra/groups"* ]]; then
                deploy_shared_stack "$user_dsd" "$package_dir"
            fi

            generate_dsd_file "$archivo_serverless" "$user_dsd"
            ;;
        1)
            log_info "Se encontró un archivo DSD existente..."

            # Seleccionar archivo serverless
            local archivo_serverless
            # Ejecutar desde paquete instalado
            local package_dir
            package_dir=$(dirname "$(dirname "$(readlink -f "$0")")")
            if ! archivo_serverless=$("$package_dir/genera_dsd_serverless/seleccionar_archivo.sh"); then
                log_error "Error al seleccionar archivo"
                exit 1
            fi

            # Verificar dependencia de shared
            if [[ "$archivo_serverless" == *"infra/groups"* ]]; then
                deploy_shared_stack "$user_dsd" "$package_dir"
            fi

            regenerate_dsd_file "$archivo_serverless" "$user_dsd"
            ;;
        *)
            log_error "Se encontraron múltiples archivos .dsd_*_serverless*.yml"
            log_info "Por favor elimina los archivos existentes para continuar"
            log_info "Ejecuta 'make dsd_rm'"
            exit 1
            ;;
    esac

    log_success "Proceso completado exitosamente"
}

# Ejecutar función principal
main "$@"
