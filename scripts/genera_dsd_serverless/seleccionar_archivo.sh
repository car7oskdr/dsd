#!/bin/bash

# Directorio base de infraestructura
DIR_INFRA="./infra"
DIR_SRC="./src"

# Inicializar variable de archivos
archivos=""

# Buscar en infra (recursivo)
if [ -d "$DIR_INFRA" ]; then
    archivos_infra=$(find "$DIR_INFRA" -name "serverless.yml" -type f 2>/dev/null | sort)
    if [ -n "$archivos_infra" ]; then
        archivos="$archivos_infra"
    fi
fi

# Buscar en src (flat, legacy)
if [ -d "$DIR_SRC" ]; then
    archivos_src=$(ls $DIR_SRC/serverless*.yml 2>/dev/null | sort)
    if [ -n "$archivos_src" ]; then
        if [ -n "$archivos" ]; then
            archivos="$archivos"$'\n'"$archivos_src"
        else
            archivos="$archivos_src"
        fi
    fi
fi

if [ -z "$archivos" ]; then
    echo "Error: No se encontraron archivos 'serverless.yml' en '$DIR_INFRA' en '$DIR_SRC'."
    exit 1
fi

# Contar archivos encontrados
total=$(echo "$archivos" | wc -l)

# Si solo hay uno, devolverlo directamente
if [ "$total" -eq 1 ]; then
    echo "$archivos"
    exit 0
fi

# Convertir a array para el select
mapfile -t archivos_array <<< "$archivos"

select archivo in "${archivos_array[@]}"; do
    if [ -n "$archivo" ]; then
        echo "$archivo"
        break
    else
        echo "Selección no válida. Intenta de nuevo."
    fi
done
