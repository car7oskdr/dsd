#!/bin/bash

ARCHIVO=$1
USER=$2

# Obtener directorio base del archivo y directorio raíz del proyecto
DIR_ARCHIVO=$(dirname "$ARCHIVO")
ROOT_DIR=$(pwd)

# Determinar el stage basado en la ruta del archivo
if [[ "$ARCHIVO" == *"/src/"* ]] || [[ "$ARCHIVO" == "./src/"* ]]; then
    STAGE="develop"
else
    STAGE="dev"
fi

# Copiar archivo al mismo directorio para mantener referencias relativas
cp "$ARCHIVO" "$DIR_ARCHIVO/.dsd-cp-serverless.yml"

source .venv/bin/activate && \
# Ejecutar desde paquete instalado
package_dir=$(dirname "$(dirname "$(readlink -f "$0")")")
python "$package_dir/genera_dsd_serverless/cambia_service.py" "$ARCHIVO" "$USER"

# Cambiar al directorio del archivo para que sls resuelva imports correctamente
cd "$DIR_ARCHIVO" || exit 1

DSD_FILE=""
if [[ "$ARCHIVO" == *"shared"* ]]; then
    DSD_FILE=".dsd-shared-serverless.yml"
else
    DSD_FILE=".dsd-serverless.yml"
fi

# Ejecutar sls print y guardar en src/.dsd-serverless.yml
if ! sls print --stage "$STAGE" -c ".dsd-service-serverless.yml" > "$ROOT_DIR/src/$DSD_FILE"; then
    echo "ERROR: sls print failed"
    exit 1
fi

if [ ! -s "$ROOT_DIR/src/$DSD_FILE" ]; then
    echo ""
    echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    echo "X                                                     X"
    echo "X     Error: No se encontró el archivo '$DSD_FILE'.   X"
    echo "X                                                     X"
    echo "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    echo ""
    # Limpiar archivos temporales antes de salir
    rm -f ".dsd-cp-serverless.yml" ".dsd-service-serverless.yml"
    exit 1
fi

# Limpiar archivos temporales
rm -f ".dsd-cp-serverless.yml" ".dsd-service-serverless.yml"
