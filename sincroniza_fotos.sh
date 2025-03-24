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
    rclone sync "$CLOUD_NAME:/" "$CLOUD_DIR" --progress --drive-shared-with-me $INCLUDE_RULE --ignore-existing --tpslimit 2 --retries 5
    if [ $? -eq 0 ]; then
        echo "Sincronización desde $CLOUD_NAME completada."
    else
        echo "Error al sincronizar desde $CLOUD_NAME."
    fi
}

# Función para detectar y descargar archivos faltantes
detect_missing_files() {
    local CLOUD_NAME=$1
    local CLOUD_DIR="$BASE_DIR/$CLOUD_NAME"
    local TEMP_LOG="/tmp/archivos_faltantes_$CLOUD_NAME.txt"
    local DATE_NOW=$(date +"%Y-%m-%d_%H-%M-%S")
    local LOG_FILE="$BASE_DIR/sincronizacion_$CLOUD_NAME-$DATE_NOW.log"
    
    echo "Analizando archivos faltantes en $CLOUD_DIR comparado con $CLOUD_NAME..."
    echo "Este proceso puede tardar un tiempo dependiendo del número de archivos."
    
    # Crear archivo de log y escribir encabezado
    echo "=== Log de sincronización de archivos faltantes ===" > "$LOG_FILE"
    echo "Fecha y hora: $(date +"%Y-%m-%d %H:%M:%S")" >> "$LOG_FILE"
    echo "Nube: $CLOUD_NAME" >> "$LOG_FILE"
    echo "Directorio local: $CLOUD_DIR" >> "$LOG_FILE"
    echo "=================================" >> "$LOG_FILE"
    
    # Determinar si es Google Photos por el nombre y ajustar rutas
    if [[ "$CLOUD_NAME" == *"Gphotos"* ]]; then
        echo "Detectado servicio de Google Photos. Ajustando rutas..."
        echo "Tipo de nube: Google Photos" >> "$LOG_FILE"
        
        # Para Google Photos, usar un enfoque basado en listas de archivos
        echo "Generando listas de archivos para comparación..."
        
        # Crear listas temporales de archivos
        REMOTE_FILES_LIST="/tmp/remote_files_$CLOUD_NAME.txt"
        LOCAL_FILES_LIST="/tmp/local_files_$CLOUD_NAME.txt"
        MISSING_FILES_LIST="/tmp/missing_files_$CLOUD_NAME.txt"
        
        # Para Google Photos, obtener lista de archivos remotos (enfocándose en media/all)
        echo "Listando archivos remotos (puede tardar varios minutos)..."
        rclone lsf --recursive "$CLOUD_NAME:/media/all" > "$REMOTE_FILES_LIST"
        
        # Obtener lista de archivos locales
        echo "Listando archivos locales..."
        if [ -d "$CLOUD_DIR/media/all" ]; then
            find "$CLOUD_DIR/media/all" -type f | sed "s|$CLOUD_DIR/media/all/||" > "$LOCAL_FILES_LIST"
        else
            # Si no existe el directorio, crear uno vacío
            mkdir -p "$CLOUD_DIR/media/all"
            touch "$LOCAL_FILES_LIST"
        fi
        
        # Encontrar archivos que están en remoto pero no en local
        echo "Identificando archivos faltantes..."
        comm -23 "$REMOTE_FILES_LIST" "$LOCAL_FILES_LIST" > "$MISSING_FILES_LIST"
        
        # Contar archivos faltantes
        MISSING_COUNT=$(wc -l < "$MISSING_FILES_LIST")
        TOTAL_REMOTE=$(wc -l < "$REMOTE_FILES_LIST")
        TOTAL_LOCAL=$(wc -l < "$LOCAL_FILES_LIST")
        
        # Registrar en el log los conteos iniciales
        echo "Total de archivos en remoto: $TOTAL_REMOTE" >> "$LOG_FILE"
        echo "Total de archivos en local: $TOTAL_LOCAL" >> "$LOG_FILE"
        echo "Archivos faltantes detectados: $MISSING_COUNT" >> "$LOG_FILE"
        
        if [ $MISSING_COUNT -eq 0 ]; then
            echo "No se encontraron archivos faltantes. ¡Todo está sincronizado!"
            echo "Estado: Completamente sincronizado" >> "$LOG_FILE"
            rm "$REMOTE_FILES_LIST" "$LOCAL_FILES_LIST" "$MISSING_FILES_LIST"
            echo "Archivo de log guardado en: $LOG_FILE"
            return 0
        fi
        
        echo "Se encontraron $MISSING_COUNT archivos faltantes en tu carpeta local."
        echo "Lista de los primeros 10 archivos faltantes (si hay tantos):"
        head -10 "$MISSING_FILES_LIST" | sed 's/^/- /' | tee -a "$LOG_FILE"
        
        read -p "¿Deseas intentar descargar todos los archivos faltantes? (s/n): " DOWNLOAD_CHOICE
        echo "Usuario eligió: $DOWNLOAD_CHOICE" >> "$LOG_FILE"
        
        if [[ "$DOWNLOAD_CHOICE" == "s" || "$DOWNLOAD_CHOICE" == "S" ]]; then
            echo "Descargando $MISSING_COUNT archivos faltantes desde $CLOUD_NAME..."
            echo "Los archivos se guardarán en: $CLOUD_DIR/media/all/"
            echo "Iniciando descarga de $MISSING_COUNT archivos..." >> "$LOG_FILE"
            
            # Variables para contar éxitos y errores
            SUCCESSFUL_DOWNLOADS=0
            FAILED_DOWNLOADS=0
            
            # Intentar descargar cada archivo faltante
            while IFS= read -r FILE_PATH; do
                echo "Descargando: $FILE_PATH"
                echo "Procesando: $FILE_PATH" >> "$LOG_FILE"
                
                # Asegurarse de que el directorio destino exista
                mkdir -p "$CLOUD_DIR/media/all/$(dirname "$FILE_PATH")"
                
                # Copiar el archivo específico desde la ruta correcta de Google Photos
                if rclone copy "$CLOUD_NAME:/media/all/$FILE_PATH" "$CLOUD_DIR/media/all/$(dirname "$FILE_PATH")" --progress; then
                    echo "✅ Éxito: $FILE_PATH" >> "$LOG_FILE"
                    SUCCESSFUL_DOWNLOADS=$((SUCCESSFUL_DOWNLOADS + 1))
                else
                    echo "❌ Error: $FILE_PATH" >> "$LOG_FILE"
                    FAILED_DOWNLOADS=$((FAILED_DOWNLOADS + 1))
                fi
            done < "$MISSING_FILES_LIST"
            
            # Resumen final en el log
            echo "=================================" >> "$LOG_FILE"
            echo "RESUMEN DE SINCRONIZACIÓN:" >> "$LOG_FILE"
            echo "Archivos procesados: $MISSING_COUNT" >> "$LOG_FILE"
            echo "Descargas exitosas: $SUCCESSFUL_DOWNLOADS" >> "$LOG_FILE"
            echo "Descargas fallidas: $FAILED_DOWNLOADS" >> "$LOG_FILE"
            echo "Archivos que aún faltan: $FAILED_DOWNLOADS" >> "$LOG_FILE"
            echo "Completado el: $(date +"%Y-%m-%d %H:%M:%S")" >> "$LOG_FILE"
            
            echo "Descarga de archivos faltantes completada."
            echo "Se descargaron exitosamente $SUCCESSFUL_DOWNLOADS de $MISSING_COUNT archivos."
            if [ $FAILED_DOWNLOADS -gt 0 ]; then
                echo "No se pudieron descargar $FAILED_DOWNLOADS archivos. Revisa el log para más detalles."
            fi
            echo "Todos los archivos han sido guardados en $CLOUD_DIR/media/all/"
            echo "Archivo de log guardado en: $LOG_FILE"
            rm "$REMOTE_FILES_LIST" "$LOCAL_FILES_LIST" "$MISSING_FILES_LIST"
        else
            echo "Operación cancelada. El registro de archivos faltantes se guardó en $MISSING_FILES_LIST"
            echo "Puedes revisar este archivo más tarde."
            echo "Sincronización cancelada por el usuario." >> "$LOG_FILE"
            echo "Archivo de log guardado en: $LOG_FILE"
        fi
    else
        # Para nubes estándar, usar el método original basado en rclone check
        echo "Tipo de nube: Estándar" >> "$LOG_FILE"
        echo "Comparando directorios usando rclone check..."
        rclone check "$CLOUD_NAME:/" "$CLOUD_DIR" $INCLUDE_RULE --missing-on-dst --one-way > "$TEMP_LOG"
        
        # Contar el número de archivos faltantes
        MISSING_COUNT=$(grep -c "^ERROR.*not in.*\"$CLOUD_DIR\"" "$TEMP_LOG")
        
        # Registrar en el log los conteos iniciales
        echo "Archivos faltantes detectados: $MISSING_COUNT" >> "$LOG_FILE"
        
        if [ $MISSING_COUNT -eq 0 ]; then
            echo "No se encontraron archivos faltantes. ¡Todo está sincronizado!"
            echo "Estado: Completamente sincronizado" >> "$LOG_FILE"
            rm "$TEMP_LOG"
            echo "Archivo de log guardado en: $LOG_FILE"
            return 0
        fi
        
        echo "Se encontraron $MISSING_COUNT archivos faltantes en tu carpeta local."
        echo "Lista de los primeros 10 archivos faltantes (si hay tantos):"
        grep "^ERROR.*not in.*\"$CLOUD_DIR\"" "$TEMP_LOG" | head -10 | sed 's/^ERROR : \(.*\): File not in ".*"/- \1/' | tee -a "$LOG_FILE"
        
        read -p "¿Deseas intentar descargar todos los archivos faltantes? (s/n): " DOWNLOAD_CHOICE
        echo "Usuario eligió: $DOWNLOAD_CHOICE" >> "$LOG_FILE"
        
        if [[ "$DOWNLOAD_CHOICE" == "s" || "$DOWNLOAD_CHOICE" == "S" ]]; then
            echo "Descargando $MISSING_COUNT archivos faltantes desde $CLOUD_NAME..."
            echo "Los archivos se guardarán en: $CLOUD_DIR/"
            echo "Iniciando descarga de $MISSING_COUNT archivos..." >> "$LOG_FILE"
            
            # Variables para contar éxitos y errores
            SUCCESSFUL_DOWNLOADS=0
            FAILED_DOWNLOADS=0
            
            # Extraer rutas de archivos faltantes
            MISSING_FILES_LOG="/tmp/missing_files_paths_$CLOUD_NAME.txt"
            grep "^ERROR.*not in.*\"$CLOUD_DIR\"" "$TEMP_LOG" | sed 's/^ERROR : \(.*\): File not in ".*"/\1/' > "$MISSING_FILES_LOG"
            
            # Intentar descargar cada archivo faltante
            while IFS= read -r FILE_PATH; do
                echo "Descargando: $FILE_PATH"
                echo "Procesando: $FILE_PATH" >> "$LOG_FILE"
                
                # Asegurarse de que el directorio destino exista
                mkdir -p "$CLOUD_DIR/$(dirname "$FILE_PATH")"
                
                # Copiar el archivo específico
                if rclone copy "$CLOUD_NAME:/$FILE_PATH" "$CLOUD_DIR/$(dirname "$FILE_PATH")" --progress; then
                    echo "✅ Éxito: $FILE_PATH" >> "$LOG_FILE"
                    SUCCESSFUL_DOWNLOADS=$((SUCCESSFUL_DOWNLOADS + 1))
                else
                    echo "❌ Error: $FILE_PATH" >> "$LOG_FILE"
                    FAILED_DOWNLOADS=$((FAILED_DOWNLOADS + 1))
                fi
            done < "$MISSING_FILES_LOG"
            
            # Resumen final en el log
            echo "=================================" >> "$LOG_FILE"
            echo "RESUMEN DE SINCRONIZACIÓN:" >> "$LOG_FILE"
            echo "Archivos procesados: $MISSING_COUNT" >> "$LOG_FILE"
            echo "Descargas exitosas: $SUCCESSFUL_DOWNLOADS" >> "$LOG_FILE"
            echo "Descargas fallidas: $FAILED_DOWNLOADS" >> "$LOG_FILE"
            echo "Archivos que aún faltan: $FAILED_DOWNLOADS" >> "$LOG_FILE"
            echo "Completado el: $(date +"%Y-%m-%d %H:%M:%S")" >> "$LOG_FILE"
            
            echo "Descarga de archivos faltantes completada."
            echo "Se descargaron exitosamente $SUCCESSFUL_DOWNLOADS de $MISSING_COUNT archivos."
            if [ $FAILED_DOWNLOADS -gt 0 ]; then
                echo "No se pudieron descargar $FAILED_DOWNLOADS archivos. Revisa el log para más detalles."
            fi
            echo "Todos los archivos han sido guardados en $CLOUD_DIR/ manteniendo su estructura de carpetas"
            echo "Archivo de log guardado en: $LOG_FILE"
            rm "$TEMP_LOG" "$MISSING_FILES_LOG"
        else
            echo "Operación cancelada. El registro de archivos faltantes se guardó en $TEMP_LOG"
            echo "Puedes revisar este archivo más tarde."
            echo "Sincronización cancelada por el usuario." >> "$LOG_FILE"
            echo "Archivo de log guardado en: $LOG_FILE"
        fi
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
echo "3) Detectar y descargar archivos faltantes"
echo "4) Salir"
read -p "Selecciona una opción (1/2/3/4): " OPTION

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
        echo "Selecciona la nube para detectar y descargar archivos faltantes:"
        select CLOUD_NAME in $CLOUDS; do
            if [ -n "$CLOUD_NAME" ]; then
                detect_missing_files "$CLOUD_NAME"
                break
            else
                echo "Opción no válida. Intenta nuevamente."
            fi
        done
        ;;
    4)
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