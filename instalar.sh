#!/bin/bash

# Colores para que se vea bonito en la terminal
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # Sin color

echo -e "${BLUE}=======================================================${NC}"
echo -e "${BLUE}    INSTALADOR AUTOMATICO DE DEPENDENCIAS - NISAR      ${NC}"
echo -e "${BLUE}=======================================================${NC}"
echo ""
echo "Este script instalara las librerias de Python y Flutter."
echo "Asegurate de tener conexion a internet."
echo ""
read -p "Presiona ENTER para continuar..."

# ---------------------------------------------------------
# 1. INSTALANDO BACKEND (PYTHON)
# ---------------------------------------------------------
echo -e "\n${BLUE}[1/2] Instalando dependencias del Backend (Python)...${NC}"

if [ ! -d "backend" ]; then
    echo -e "${RED}❌ Error: No se encuentra la carpeta 'backend'. Asegurate de ejecutar este script desde la raiz del proyecto.${NC}"
    exit 1
fi

cd backend

# Crear entorno virtual si no existe (Recomendado en Arch/Linux)
if [ ! -d ".venv" ]; then
    echo "Creando entorno virtual (.venv)..."
    python -m venv .venv
fi

# Activar el entorno virtual
source .venv/bin/activate

# Actualizar pip e instalar requerimientos
python -m pip install --upgrade pip
python -m pip install -r requirements.txt

if [ $? -ne 0 ]; then
    echo -e "\n${RED}❌ Hubo un error al instalar Python. Revisa que tengas Python instalado y las dependencias del sistema (como gdal, proj, hdf5 en Arch).${NC}"
    exit 1
fi

# ---------------------------------------------------------
# 2. INSTALANDO FRONTEND (FLUTTER)
# ---------------------------------------------------------
echo -e "\n${BLUE}[2/2] Instalando dependencias del Frontend (Flutter)...${NC}"

cd ../mobile

# Verificar si Flutter está instalado
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Error: Flutter no está instalado o no está en el PATH.${NC}"
    exit 1
fi

flutter pub get

if [ $? -ne 0 ]; then
    echo -e "\n${RED}❌ Hubo un error al instalar Flutter. Revisa tu instalación de Flutter.${NC}"
    exit 1
fi

# ---------------------------------------------------------
# FINALIZADO
# ---------------------------------------------------------
echo ""
echo -e "${GREEN}=======================================================${NC}"
echo -e "${GREEN}✅ ¡TODO INSTALADO CON EXITO!${NC}"
echo -e "${GREEN}=======================================================${NC}"
echo ""
echo 'Ya puedes ejecutar "./iniciar.sh" para arrancar el proyecto.'
echo ""

# Pausa para que puedas leer los mensajes antes de que se cierre la terminal
read -p "Presiona ENTER para salir..."