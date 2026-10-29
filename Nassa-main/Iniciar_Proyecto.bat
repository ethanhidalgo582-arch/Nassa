@echo off
title Lanzador NISAR
color 0A

echo =======================================================
echo     INICIANDO PROYECTO NISAR + IA
echo =======================================================
echo.
echo [1/2] Abriendo el servidor Backend (Python)...
:: Ya no llamamos al .venv, usamos el Python de tu PC directo
start "NISAR Backend" cmd /k "cd backend && python -m uvicorn main:app --reload --host 127.0.0.1 --port 8000"

:: Esperamos 3 segundos para que Python arranque antes de abrir Flutter
timeout /t 3 /nobreak >nul

echo [2/2] Abriendo la interfaz Frontend (Flutter)...
start "NISAR Frontend" cmd /k "cd mobile && flutter run -d chrome --web-port 3000"

echo.
echo ¡Todo listo! Revisa las ventanas que se acaban de abrir.
timeout /t 5 >nul
exit