$ErrorActionPreference="Stop"
Set-Location $PSScriptRoot
$python=Join-Path $PSScriptRoot "backend/.venv/Scripts/python.exe"
if (!(Test-Path $python)) { throw "Primero ejecuta Instalar.ps1." }
$backend=Join-Path $PSScriptRoot "backend"
$server = Start-Process -PassThru -FilePath $python -ArgumentList "-m","uvicorn","main:app","--host","127.0.0.1","--port","8000" -WorkingDirectory $backend -WindowStyle Hidden -RedirectStandardOutput (Join-Path $backend "server.log") -RedirectStandardError (Join-Path $backend "server-error.log")
Push-Location mobile
try { flutter run -d chrome --web-port 3000 } finally { Pop-Location; if (!$server.HasExited) { Stop-Process -Id $server.Id -ErrorAction SilentlyContinue } }

