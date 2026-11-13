param([string]$Python = "python")
$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot
& $Python -m venv backend/.venv
if ($LASTEXITCODE -ne 0) { throw "No se pudo crear el entorno Python." }
& ./backend/.venv/Scripts/python.exe -m pip install -r backend/requirements.txt
if ($LASTEXITCODE -ne 0) { throw "Falló la instalación de dependencias." }
if (!(Test-Path backend/.env)) { Copy-Item backend/.env.example backend/.env }
Push-Location mobile
try { flutter pub get; if ($LASTEXITCODE -ne 0) { throw "Falló flutter pub get." } } finally { Pop-Location }
Write-Host "Instalación completada. Configura backend/.env y ejecuta Iniciar.ps1."

