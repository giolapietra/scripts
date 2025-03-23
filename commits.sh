#!/bin/sh

# Procesa los parámetros del script
while [ "$1" != "" ]; do
    case $1 in
        --omail ) shift
                  OLD_EMAIL="$1"
                  ;;
        --nmail ) shift
                  NEW_EMAIL="$1"
                  ;;
        --oname ) shift
                  OLD_NAME="$1"
                  ;;
        --nname ) shift
                  NEW_NAME="$1"
                  ;;
        * )       REPO_URL=$1
                  ;;
    esac
    shift
done

# Verifica que se hayan proporcionado los parámetros obligatorios
if [ -z "$OLD_EMAIL" ] || [ -z "$NEW_EMAIL" ] || [ -z "$OLD_NAME" ] || [ -z "$NEW_NAME" ] || [ -z "$REPO_URL" ]; then
    echo "Uso: ./commits.sh --omail <correo_antiguo> --nmail <correo_nuevo> --oname <nombre_antiguo> --nname <nombre_nuevo> {repo-git}"
    exit 1
fi

# Verifica si se proporcionó el enlace del repositorio como parámetro
if [ -z "$REPO_URL" ]; then
    echo "Error: No se proporcionó un enlace válido para el repositorio Git."
    exit 1
fi

# Clona el repositorio en la carpeta Scripts/
# Obtiene el nombre del repositorio de la URL
REPO_NAME=$(basename "$REPO_URL" .git)

# Define la ruta de destino para clonar el repositorio
REPO_NAME=$(basename "$REPO_URL" .git)
DEST_DIR="$REPO_NAME"

# Verifica si la carpeta de destino ya existe y no está vacía
if [ -d "$DEST_DIR" ] && [ "$(ls -A "$DEST_DIR")" ]; then
    echo "La carpeta de destino '$DEST_DIR' ya existe y no está vacía."
    echo "¿Deseas eliminarla y clonar nuevamente el repositorio? (y/n)"
    read DELETE_EXISTING
    if [ "$DELETE_EXISTING" = "y" ]; then
        rm -rf "$DEST_DIR"
        echo "Carpeta eliminada."
    else
        echo "Operación cancelada."
        exit 0
    fi
fi

# Clona el repositorio en la carpeta con el nombre del repo
git clone "$REPO_URL" "$DEST_DIR"
if [ $? -ne 0 ]; then
    echo "Error: No se pudo clonar el repositorio. Verifica el enlace proporcionado."
    exit 1
fi

# Cambia al directorio del repositorio clonado
cd "$DEST_DIR" || exit 1

# Opción para revisar el historial de commits después de clonar
echo "¿Deseas revisar el historial de commits antes de comenzar? (y/n)"
read REVIEW_COMMITS
if [ "$REVIEW_COMMITS" = "y" ]; then
    echo "Mostrando el historial de commits con autor, usuario y correo..."
    git log --pretty=format:"%h - %an (%ae) - %s" --graph --all
    echo "¿Deseas continuar con el script? (y/n)"
    read CONTINUE_SCRIPT
    if [ "$CONTINUE_SCRIPT" != "y" ]; then
        echo "Operación cancelada."
        exit 0
    fi
fi

# Verifica si el repositorio está conectado a GitHub
REMOTE_URL=$(git config --get remote.origin.url)
if [[ "$REMOTE_URL" != *"github.com"* ]]; then
    echo "Error: Este repositorio no está conectado a GitHub."
    exit 1
fi

# Verifica si el script se está ejecutando dentro de un repositorio Git
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "Error: Este script debe ejecutarse dentro de un repositorio Git."
    exit 1
fi

# Solicita confirmación antes de proceder
echo "Este script modificará el historial de commits del repositorio. ¿Deseas continuar? (y/n)"
read CONFIRMATION
if [ "$CONFIRMATION" != "y" ]; then
    echo "Operación cancelada."
    exit 0
fi

# Script para corregir el autor de los commits en un repositorio Git
# Reemplaza los commits realizados con un correo antiguo (personal) por el nuevo (corporativo)

# Cambia estos valores según corresponda
OLD_EMAIL="jerexxypunto@gmail.com"
NEW_NAME="Jeremías San Martín"
NEW_EMAIL="jeremias@reevolutiva.com"

# Verifica si git-filter-repo está instalado
if ! command -v git-filter-repo > /dev/null 2>&1; then
    echo "Error: git-filter-repo no está instalado. Instálalo con 'pip install git-filter-repo'."
    exit 1
fi

# Solicita confirmación para usar --force si no es un clon fresco
echo "El repositorio no parece ser un clon fresco. ¿Deseas forzar la operación? (y/n)"
read FORCE_OPERATION
if [ "$FORCE_OPERATION" = "y" ]; then
    FORCE_FLAG="--force"
else
    echo "Operación cancelada."
    exit 0
fi

# Ajusta la revisión de consistencia de los commits
# Verifica si los commits tienen el correo y nombre correctos antes de aplicar cambios
echo "Revisando consistencia de los commits..."
MISSING_COMMITS=$(git log --all --format='%an <%ae>' | grep "$OLD_EMAIL")
if [ -z "$MISSING_COMMITS" ]; then
    echo "Todos los commits ya tienen el correo y nombre correctos."
else
    echo "Se encontraron commits que necesitan ser actualizados. Continuando con el script..."

    # Ejecuta la corrección del historial usando git-filter-repo
    git filter-repo $FORCE_FLAG --commit-callback '
    if commit.author_email == b"'"$OLD_EMAIL"'":
        commit.author_name = b"'"$NEW_NAME"'"
        commit.author_email = b"'"$NEW_EMAIL"'"
    if commit.committer_email == b"'"$OLD_EMAIL"'":
        commit.committer_name = b"'"$NEW_NAME"'"
        commit.committer_email = b"'"$NEW_EMAIL"'"
    '
fi

# Verifica si el repositorio está conectado a GitHub correctamente
REMOTE_URL=$(git config --get remote.origin.url)
if [ -z "$REMOTE_URL" ] || [[ "$REMOTE_URL" != *"github.com"* ]]; then
    echo "Error: Este repositorio no está conectado a un repositorio GitHub válido."
    exit 1
fi

# Elimina el uso de iconv y utiliza el nombre directamente
ascii_name=$(echo "$NEW_NAME" | iconv -f utf-8 -t ascii//translit)

# Ejecuta la corrección del historial usando git-filter-repo con la opción --force si es necesario
git filter-repo $FORCE_FLAG --commit-callback '
if not commit.author_email:
    commit.author_email = b"'"$default_email"'"
    commit.author_name = b"'"$default_name"'"
if not commit.committer_email:
    commit.committer_email = b"'"$default_email"'"
    commit.committer_name = b"'"$default_name"'"
if commit.author_email == b"'"$OLD_EMAIL"'":
    commit.author_name = b"'"$ascii_name"'"
    commit.author_email = b"'"$NEW_EMAIL"'"
if commit.committer_email == b"'"$OLD_EMAIL"'":
    commit.committer_name = b"'"$ascii_name"'"
    commit.committer_email = b"'"$NEW_EMAIL"'"
'

# Confirma que los cambios se realizaron correctamente
echo "¿Deseas verificar los cambios realizados en el historial de commits? (y/n)"
read VERIFY_CHANGES
if [ "$VERIFY_CHANGES" = "y" ]; then
    git log --all --format='%an <%ae>' | grep "$NEW_EMAIL"
    if [ $? -eq 0 ]; then
        echo "Los cambios se realizaron correctamente."
    else
        echo "Error: No se encontraron commits con el nuevo correo."
    fi
fi

# Verifica si el remoto 'origin' ya existe antes de agregarlo
if ! git remote | grep -q '^origin$'; then
    echo "Volviendo a agregar el remoto 'origin'..."
    git remote add origin "$REPO_URL"
else
    echo "El remoto 'origin' ya existe."
fi

# Fuerza el push de los cambios al repositorio remoto
echo "Forzando el push de los cambios al repositorio remoto..."
git push --force --tags origin 'refs/heads/*'

# Verifica si el push fue exitoso
if [ $? -eq 0 ]; then
    echo "Los cambios se han subido correctamente al repositorio remoto."
else
    echo "Error: No se pudieron subir los cambios al repositorio remoto."
    exit 1
fi

# Pregunta si se desea eliminar la carpeta del repositorio
cd - > /dev/null 2>&1
echo "¿Deseas eliminar la carpeta del repositorio de este equipo? (y/n)"
read DELETE_REPO
if [ "$DELETE_REPO" = "y" ]; then
    rm -rf "$DEST_DIR"
    echo "Carpeta del repositorio eliminada."
else
    echo "La carpeta del repositorio se ha conservado."
fi

# Nota:
# git-filter-repo es más eficiente y seguro que git filter-branch.
# Después de ejecutar este script debes forzar el push al repositorio remoto:
# git push --force --tags origin 'refs/heads/*'
