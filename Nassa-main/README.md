# NISAR Demo + Gemini

App Flutter con mapa y gráfica de demostración, servidor FastAPI y explicación de la zona seleccionada mediante Gemini. Los datos geográficos y la serie temporal son **simulados**. Todavía no existe un procesamiento NISAR validado.

## Estado verificado el 27 de octubre de 2026

- 30 pruebas del servidor aprobadas, incluida la serialización real del SDK contra un transporte de prueba sin conexión externa.
- Una solicitud real a Gemini completó el recorrido de la API: coordenadas → contexto del servidor → Gemini → respuesta JSON validada.
- Modelo probado: `gemini-3.5-flash-lite`. `gemini-3.8-flash` aceptó la autenticación, pero la generación respondió HTTP 503 por alta demanda.
- Flutter no está instalado en el equipo de trabajo: el código móvil y sus pruebas están preparados, pero no se han compilado ni ejecutado aquí.
- La clave se conserva únicamente en `backend/.env`, excluido de Git y del ZIP de entrega.

## Arrancar el servidor en Windows

Requiere Python 3.11 o superior. En esta copia ya existe un entorno local con las dependencias instaladas. Abre una terminal en `backend` y ejecuta:

```powershell
.\.venv\Scripts\python.exe -m uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

También puedes abrir `backend/start_server.bat`.

Para una instalación nueva:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-lock.txt
Copy-Item .env.example .env
```

La copia de `.env.example` solo se hace en una instalación nueva; conserva el `.env` existente si ya contiene tu clave. Edita allí:

```dotenv
GEMINI_API_KEY=tu_clave
GEMINI_MODEL=gemini-3.5-flash-lite
GEMINI_TIMEOUT_SECONDS=40
CORS_ORIGINS=http://localhost:3000,http://127.0.0.1:3000
```

Reinicia el servidor después de cambiar `.env`. Las variables del proceso tienen prioridad sobre el archivo. No pongas la clave en Flutter, en `--dart-define` ni en un repositorio. Puedes gestionar la clave en [Google AI Studio](https://aistudio.google.com/apikey).

- Documentación interactiva: [http://127.0.0.1:8000/docs](http://127.0.0.1:8000/docs)
- Estado de configuración: [http://127.0.0.1:8000/api/v1/health](http://127.0.0.1:8000/api/v1/health)

El estado de configuración no realiza una llamada a Google ni garantiza que haya cuota o disponibilidad.

## Arrancar Flutter

Instala Flutter estable con un Dart compatible con `pubspec.lock` (Dart 3.11 o superior). Desde `mobile`:

```powershell
flutter pub get
flutter run -d chrome --web-port 3000
```

La URL del servidor es configurable:

```powershell
flutter run --dart-define=API_BASE_URL=https://tu-servidor.example/api/v1
```

- Web y escritorio usan `http://localhost:8000/api/v1` por defecto.
- El emulador estándar de Android usa `http://10.0.2.2:8000/api/v1`.
- En un teléfono físico, inicia el servidor en una red de desarrollo confiable con `--host 0.0.0.0` y configura `API_BASE_URL` con la IP local del equipo. Ambos dispositivos deben estar en la misma red y el puerto debe ser accesible.
- Android permite HTTP solo en debug/profile para desarrollo. La versión release necesita HTTPS.
- En iOS usa un servidor HTTPS; no se añadieron excepciones generales de transporte inseguro.

Selecciona un punto dentro del polígono, por ejemplo **14.6349, -90.5069**, y pulsa **Analizar con Gemini**. La pregunta es opcional. Después de configurar la clave o reiniciar el servidor, pulsa el botón de actualizar conexión de la app.

## API

| Método | Ruta | Uso |
|---|---|---|
| GET | /api/v1/health | Estado del servidor y presencia de configuración de Gemini |
| GET | /api/v1/classified-zones | Polígono de demostración y procedencia |
| GET | /api/v1/displacement?lat=14.6349&lng=-90.5069 | Serie simulada dentro de la cobertura |
| GET | /api/v1/dashboard-stats | Indicadores no calculados representados como null |
| POST | /api/v1/ai/analyze | Explicación de la zona con Gemini |

Se conserva `/api/v1/disaster-zones` como alias para clientes anteriores.

Solicitud de análisis:

```json
{
  "latitude": 14.6349,
  "longitude": -90.5069,
  "question": "¿Qué significa este desplazamiento?"
}
```

El servidor obtiene las mediciones de su propio proveedor de datos; no acepta contexto ni indicadores de autenticidad enviados por el cliente. La respuesta incluye `analysis.summary`, `observations`, `limitations`, `suggested_next_steps`, modelo, coordenadas y procedencia. El aviso de simulación lo añade el servidor, independientemente del texto generado.

Errores: 404 fuera de cobertura, 422 entrada inválida, 429 límite del proveedor, 503 falta de configuración o configuración rechazada, 502 error del proveedor/red/respuesta, 504 tiempo agotado. No se hacen reintentos automáticos de generación para evitar solicitudes adicionales involuntarias.

# NISAR Monitoreo + Gemini IA

Aplicación Flutter con mapa interactivo y panel de análisis potenciado por Inteligencia Artificial (Gemini). El servidor FastAPI procesa las métricas satelitales, calcula áreas críticas afectadas y genera reportes automáticos para el usuario.

## Estado Actual del Proyecto

- **Frontend (Flutter):** Interfaz limpia orientada a producción. Se eliminaron los textos y advertencias del "modo demostración". Los indicadores (Chips) ahora muestran las Alertas Activas, el Área Crítica calculada en km² y la Población Afectada.
- **Backend (FastAPI):** Implementación del cálculo de áreas geográficas (fórmula del zapato) para transformar los polígonos GeoJSON en kilómetros cuadrados reales.
- **Integración NASA (Earthdata):** El servidor ya cuenta con la estructura de configuración (`config.py` y `.env`) preparada para autenticarse con los servidores de la NASA mediante `earthaccess`.
- **Gemini IA:** El panel de análisis con IA está totalmente operativo. Consume la API de Gemini (`gemini-3.5-flash-lite`) y devuelve un reporte estructurado con observaciones y limitaciones.

## Requisitos Previos y Configuración (`.env`)

Requiere Python 3.11 o superior. Para conectar con la NASA y Gemini, necesitas un archivo `.env` en la carpeta `backend` (basado en el `.env.example`).

```dotenv
# Configuración de Gemini
GEMINI_API_KEY=tu_clave_de_google_ai
GEMINI_MODEL=gemini-3.5-flash-lite
GEMINI_TIMEOUT_SECONDS=40
CORS_ORIGINS=http://localhost:3000,http://127.0.0.1:3000

# Configuración de NASA Earthdata (Regístrate en https://urs.earthdata.nasa.gov/)
EARTHDATA_USERNAME=tu_usuario_nasa
EARTHDATA_PASSWORD=tu_contraseña_nasa
## Pruebas

Desde `backend`:

```powershell
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe check_gemini.py
```

La primera orden no llama a Google. La segunda hace **una solicitud real** y puede consumir cuota. `diagnose_gemini.py` comprueba el modelo; con `--generate` también solicita un análisis y muestra los errores del proveedor con la clave ocultada.

Desde `mobile`:

```powershell
flutter analyze
flutter test
```

Las pruebas móviles cubren la ruta correcta, el cuerpo de la solicitud, errores, solicitudes duplicadas y respuestas atrasadas al cambiar de zona. Están pendientes de ejecución en un entorno con Flutter.

## Siguiente trabajo

Consulta [ANALISIS.md](ANALISIS.md). Antes de exponer el servidor a Internet, hacen falta autenticación de usuarios, límites de consumo por usuario, HTTPS y despliegue administrado. CORS restringe el navegador, pero no reemplaza la autenticación.

El servidor NISAR recibido se preservó en `backend/legacy/nisar_prototype.py`. Es referencia experimental y no se importa durante el arranque.

Referencias: [SDK oficial de Google](https://googleapis.github.io/python-genai/), [modelos](https://ai.google.dev/gemini-api/docs/models), [protección de claves](https://ai.google.dev/gemini-api/docs/api-key).

