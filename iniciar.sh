#!/bin/bash

# Colores para la terminal
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # Sin color

echo -e "${BLUE}=======================================================${NC}"
echo -e "${BLUE}    INICIANDO PROYECTO NISAR + IA (LINUX)              ${NC}"
echo -e "${BLUE}=======================================================${NC}"
echo ""

# ---------------------------------------------------------
# 1. INICIAR BACKEND
# ---------------------------------------------------------
echo -e "${BLUE}[1/2] Abriendo el servidor Backend (Python) en el puerto 8080...${NC}"

# Detectar qué emulador de terminal está disponible en tu sistema
if command -v gnome-terminal &> /dev/null; then
    gnome-terminal --title="NISAR Backend" -- bash -c "cd backend && source .venv/bin/activate && python -m uvicorn main:app --reload --host 127.0.0.1 --port 8080; exec bash"
elif command -v konsole &> /dev/null; then
    konsole --title "NISAR Backend" -e bash -c "cd backend && source .venv/bin/activate && python -m uvicorn main:app --reload --host 127.0.0.1 --port 8080; exec bash" &
elif command -v xfce4-terminal &> /dev/null; then
    xfce4-terminal --title="NISAR Backend" -e "bash -c 'cd backend && source .venv/bin/activate && python -m uvicorn main:app --reload --host 127.0.0.1 --port 8080; exec bash'" &
elif command -v x-terminal-emulator &> /dev/null; then
    x-terminal-emulator -e "bash -c 'cd backend && source .venv/bin/activate && python -m uvicorn main:app --reload --host 127.0.0.1 --port 8080; exec bash'" &
else
    echo "⚠️ No se detectó un emulador de terminal gráfico. Ejecutando en segundo plano..."
    (cd backend && source .venv/bin/activate && python -m uvicorn main:app --reload --host 127.0.0.1 --port 8080) &
fi

# Esperamos 4 segundos para que Python arranque
sleep 4

# ---------------------------------------------------------
# 2. INICIAR FRONTEND CON FIREFOX
# ---------------------------------------------------------
echo -e "${BLUE}[2/2] Abriendo la interfaz Frontend (Flutter) en modo web-server...${NC}"

# Detectamos si xdg-open está disponible para abrir Firefox
if command -v xdg-open &> /dev/null; then
    # Esperamos unos segundos en segundo plano y luego abrimos Firefox
    (sleep 5 && xdg-open http://localhost:3000) &
else
    echo "⚠️ No se encontró xdg-open. Abre http://localhost:3000 manualmente en tu navegador."
fi

# Detectar emulador de terminal para Flutter
if command -v gnome-terminal &> /dev/null; then
    gnome-terminal --title="NISAR Frontend" -- bash -c "cd mobile && flutter run -d web-server --web-port 3000; exec bash"
elif command -v konsole &> /dev/null; then
    konsole --title "NISAR Frontend" -e bash -c "cd mobile && flutter run -d web-server --web-port 3000; exec bash" &
elif command -v xfce4-terminal &> /dev/null; then
    xfce4-terminal --title="NISAR Frontend" -e "bash -c 'cd mobile && flutter run -d web-server --web-port 3000; exec bash'" &
elif command -v x-terminal-emulator &> /dev/null; then
    x-terminal-emulator -e "bash -c 'cd mobile && flutter run -d web-server --web-port 3000; exec bash'" &
else
    (cd mobile && flutter run -d web-server --web-port 3000) &
fi

echo ""
echo -e "${GREEN}¡Todo listo! Revisa las ventanas que se acaban de abrir.${NC}"
sleep 3