@echo off
:: AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
:: Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
setlocal
title Instalador IMPACT
color 0B
cd /d "%~dp0"

echo =======================================================
echo     INSTALADOR DE DEPENDENCIAS - IMPACT
echo =======================================================
echo Requiere Python 3.12+ (probado con 3.14) y Flutter en el PATH.
echo.

:: --- Elegir Python: primero el lanzador "py", si no "python" ---
set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY (
    where python >nul 2>&1 && set "PY=python"
)
if not defined PY (
    echo [ERROR] No se encontro Python. Instalalo desde https://www.python.org/downloads/
    pause & exit /b 1
)
%PY% -c "import sys; sys.exit(0 if sys.version_info >= (3,12) else 1)"
if errorlevel 1 (
    echo [ERROR] Se necesita Python 3.12 o superior. Version detectada:
    %PY% --version
    pause & exit /b 1
)
%PY% --version

echo.
echo [1/3] Entorno virtual del backend...
:: Un .venv creado en Linux/Mac no tiene Scripts\python.exe: se borra y se recrea.
if exist "backend\.venv\" if not exist "backend\.venv\Scripts\python.exe" (
    echo El .venv existente no es de Windows. Recreandolo...
    rmdir /s /q "backend\.venv"
)
if not exist "backend\.venv\Scripts\python.exe" (
    %PY% -m venv "backend\.venv"
    if errorlevel 1 (
        echo [ERROR] No se pudo crear el entorno virtual.
        pause & exit /b 1
    )
)
set "VPY=%~dp0backend\.venv\Scripts\python.exe"

echo.
echo [2/3] Instalando librerias de Python (puede tardar varios minutos)...
"%VPY%" -m pip install --upgrade pip
"%VPY%" -m pip install -r "backend\requirements.txt"
if errorlevel 1 (
    echo [ERROR] Fallo la instalacion de librerias de Python.
    pause & exit /b 1
)
"%VPY%" -c "import fastapi, uvicorn, httpx, google.genai, earthaccess, h5py, numpy, shapely, pyproj, rasterio, PIL; print('Librerias de Python OK')"
if errorlevel 1 (
    echo [ERROR] Alguna libreria no se importa correctamente.
    pause & exit /b 1
)

if not exist "backend\.env" (
    if exist "backend\.env.example" (
        copy "backend\.env.example" "backend\.env" >nul
        echo Se creo backend\.env: rellena tus claves ^(Gemini, Earthdata^).
    ) else (
        echo [AVISO] No existe backend\.env. Crealo con tus claves antes de iniciar.
    )
)

echo.
echo [3/3] Instalando dependencias de Flutter...
where flutter >nul 2>&1
if errorlevel 1 (
    echo [ERROR] No se encontro Flutter en el PATH.
    pause & exit /b 1
)
pushd mobile
call flutter pub get
set "FERR=%errorlevel%"
popd
if not "%FERR%"=="0" (
    echo [ERROR] Fallo flutter pub get.
    pause & exit /b 1
)

echo.
echo =======================================================
echo   TODO INSTALADO. Ahora ejecuta iniciar.bat
echo =======================================================
pause
