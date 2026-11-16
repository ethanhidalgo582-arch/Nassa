@echo off
:: AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
:: Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
setlocal
title Lanzador IMPACT
color 0A
cd /d "%~dp0"

set "PORT=8000"
set "VPY=%~dp0backend\.venv\Scripts\python.exe"

echo =======================================================
echo     INICIANDO IMPACT
echo =======================================================

if not exist "%VPY%" (
    echo [ERROR] No hay entorno de Python para Windows. Ejecuta primero instalar.bat
    pause & exit /b 1
)
if not exist "backend\.env" echo [AVISO] No existe backend\.env: Gemini y Earthdata no funcionaran sin tus claves.

echo [1/2] Backend en http://127.0.0.1:%PORT% ...
start "IMPACT Backend" cmd /k "cd /d "%~dp0backend" && "%VPY%" -m uvicorn main:app --host 127.0.0.1 --port %PORT%"

:: Esperar a que el backend responda (maximo ~40 s)
set /a TRIES=0
:wait
set /a TRIES+=1
"%VPY%" -c "import urllib.request,sys; urllib.request.urlopen('http://127.0.0.1:%PORT%/api/v1/health', timeout=2)" >nul 2>&1
if not errorlevel 1 goto ready
if %TRIES% GEQ 20 (
    echo [AVISO] El backend aun no responde; revisa la ventana "IMPACT Backend".
    goto front
)
timeout /t 2 /nobreak >nul
goto wait

:ready
echo Backend listo.

:front
echo [2/2] Frontend Flutter en Chrome ^(puerto 3000^)...
start "IMPACT Frontend" cmd /k "cd /d "%~dp0mobile" && flutter run -d chrome --web-port 3000 --dart-define=API_BASE_URL=http://127.0.0.1:%PORT%/api/v1"

echo.
echo Listo. Revisa las ventanas que se abrieron.
timeout /t 5 >nul
exit /b 0
