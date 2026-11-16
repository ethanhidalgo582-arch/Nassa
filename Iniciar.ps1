# Arranque local en Windows: backend (FastAPI, puerto 8000) + frontend Flutter en Chrome.
# Requisitos: haber ejecutado Instalar.ps1 y tener backend/.env con tus claves.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$python = Join-Path $PSScriptRoot "backend/.venv/Scripts/python.exe"
if (!(Test-Path $python)) { throw "Primero ejecuta Instalar.ps1." }
if (!(Test-Path (Join-Path $PSScriptRoot "backend/.env"))) { Write-Warning "No existe backend/.env: copia backend/.env.example y rellena las claves." }
$backend = Join-Path $PSScriptRoot "backend"
$server = Start-Process -PassThru -FilePath $python `
  -ArgumentList "-m","uvicorn","main:app","--host","127.0.0.1","--port","8000" `
  -WorkingDirectory $backend -WindowStyle Hidden `
  -RedirectStandardOutput (Join-Path $backend "server.log") -RedirectStandardError (Join-Path $backend "server-error.log")
Push-Location mobile
try {
  flutter run -d chrome --web-port 3000 --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
} finally {
  Pop-Location
  if (!$server.HasExited) { Stop-Process -Id $server.Id -ErrorAction SilentlyContinue }
}
