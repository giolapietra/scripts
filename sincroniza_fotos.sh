#!/bin/bash

# Define BASE_DIR como una subcarpeta "Fotos" en el directorio del script
BASE_DIR="$(dirname "$0")/Fotos"

# Definimos las extensiones que consideramos fotos o videos
EXTENSIONS="jpg,jpeg,png,heic,heif,webp,bmp,tiff,raw,cr2,arw,dng,gif,mp4,mov,avi,mkv"

# Construimos el filtro de include para rclone
INCLUDE_RULE="--include *.{${EXTENSIONS}}"

# Función para listar las nubes configuradas en rclone y crear carpetas dinámicamente
setup_clouds() {
    echo "Listando nubes configuradas en rclone..."
    CLOUDS=$(rclone listremotes | sed 's/:$//')

    for CLOUD in $CLOUDS; do
        CLOUD_DIR="$BASE_DIR/$CLOUD"
        echo "Creando carpeta local para $CLOUD en $CLOUD_DIR..."
        mkdir -p "$CLOUD_DIR"
    done
}

# Función para sincronizar desde una nube específica
sync_from_cloud() {
    local CLOUD_NAME=$1
    local CLOUD_DIR="$BASE_DIR/$CLOUD_NAME"

    echo "Sincronizando fotos y videos desde $CLOUD_NAME..."
    rclone sync "$CLOUD_NAME:/" "$CLOUD_DIR" --progress --drive-shared-with-me $INCLUDE_RULE --ignore-existing
    if [ $? -eq 0 ]; then
        echo "Sincronización desde $CLOUD_NAME completada."
    else
        echo "Error al sincronizar desde $CLOUD_NAME."
    fi
}

# Función para listar la estructura de carpetas en una nube específica
list_cloud_structure() {
    local CLOUD_NAME=$1
    echo "Verificando estructura de carpetas en $CLOUD_NAME..."
    rclone lsd "$CLOUD_NAME:/" --drive-shared-with-me
}

# Configurar las nubes dinámicamente
setup_clouds

# Mejora en la interacción del script para hacerlo más claro y amigable
# Agrega un encabezado para informar al usuario sobre el propósito del script
echo "=============================="
echo " Sincronización de Fotos y Videos "
echo "=============================="
echo "Este script te permite sincronizar fotos y videos desde nubes configuradas en rclone."
echo ""

# Modifica el menú para hacerlo más claro y agregar una opción de salida
echo "¿Qué deseas hacer?"
echo "1) Sincronizar desde una nube específica"
echo "2) Ver estructura de carpetas en una nube específica"
echo "3) Salir"
read -p "Selecciona una opción (1/2/3): " OPTION

case $OPTION in
    1)
        echo "Selecciona la nube desde la cual sincronizar:"
        select CLOUD_NAME in $CLOUDS; do
            if [ -n "$CLOUD_NAME" ]; then
                sync_from_cloud "$CLOUD_NAME"
                break
            else
                echo "Opción no válida. Intenta nuevamente."
            fi
        done
        ;;
    2)
        echo "Selecciona la nube para ver su estructura de carpetas:"
        select CLOUD_NAME in $CLOUDS; do
            if [ -n "$CLOUD_NAME" ]; then
                list_cloud_structure "$CLOUD_NAME"
                break
            else
                echo "Opción no válida. Intenta nuevamente."
            fi
        done
        ;;
    3)
        echo "Saliendo del script. ¡Hasta luego!"
        exit 0
        ;;
    *)
        echo "Opción no válida. Saliendo..."
        exit 1
        ;;
esac

# Mejora en el mensaje final para mayor claridad
echo "Sincronización completa. Las fotos y videos están en: $BASE_DIR"
echo "Puedes revisar las carpetas sincronizadas en tu explorador de archivos."

# Abre la carpeta consolidada solo si existe
if [ -d "$BASE_DIR" ]; then
    echo "Abriendo carpeta consolidada..."
    open "$BASE_DIR"
else
    echo "La carpeta consolidada no existe. Verifica si hubo algún problema."
fi

echo "¡Listo para organizar en digiKam! 😎"