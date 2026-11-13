@echo off
title Instalador de Dependencias NISAR
color 0B

echo =======================================================
echo     INSTALADOR AUTOMATICO DE DEPENDENCIAS - NISAR
echo =======================================================
echo.
echo Este script instalara las librerias de Python y Flutter.
echo Asegurate de tener conexion a internet.
echo.
pause

echo.
echo [1/2] Instalando dependencias del Backend (Python)...
cd backend
python -m pip install --upgrade pip
python -m pip install -r requirements.txt

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ❌ Hubo un error al instalar Python. Revisa que tengas Python instalado.
    pause
    exit /b
)

echo.
echo [2/2] Instalando dependencias del Frontend (Flutter)...
cd ../mobile
flutter pub get

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ❌ Hubo un error al instalar Flutter. Revisa que tengas Flutter en tus variables de entorno.
    pause
    exit /b
)

echo.
echo =======================================================
echo ✅ ¡TODO INSTALADO CON EXITO!
echo =======================================================
echo.
echo Ya puedes cerrar esta ventana y ejecutar "Iniciar_Proyecto.bat".
echo.
pause