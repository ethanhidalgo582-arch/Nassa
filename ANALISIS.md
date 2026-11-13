# Revisión de la app y trabajo pendiente

Revisión del proyecto NISAR, actualizada tras las últimas mejoras de interfaz y backend.

## Lo que ya tiene el proyecto (Actualizado)

- **Flutter:** Mapa de OpenStreetMap, polígonos, selección de punto, gráfica y panel de estadísticas. Interfaz limpia orientada a producción (sin textos de "demostración").
- **FastAPI:** Endpoints para zonas clasificadas, desplazamiento y estadísticas. Implementación del cálculo real de áreas afectadas en km².
- **Integración de IA:** Flujo completo con Gemini (resumen, observaciones, limitaciones y próximos pasos).
- **Prototipo NISAR:** Script preparado con `earthaccess` y `h5py` para descargar y procesar productos satelitales.
- **Configuración Segura:** Manejo de credenciales de NASA Earthdata a través de variables de entorno (`.env`).

## Hallazgos corregidos recientemente

| Hallazgo previo | Consecuencia | Estado Actual |
|---|---|---|
| Área y población constantes | Indicadores sin cálculo real | **Corregido:** El área ahora se calcula dinámicamente mediante la fórmula del zapato (Shoelace) sobre los polígonos. |
| Interfaz mostraba advertencias de "demostración" | Apariencia de prototipo | **Corregido:** Textos actualizados a "Monitoreo Satelital NISAR". |
| Credenciales de NASA no configurables | Inicio dependiente de variables hardcodeadas | **Corregido:** `config.py` lee `EARTHDATA_USERNAME` y `EARTHDATA_PASSWORD` desde `.env`. |
| Valores aleatorios si faltaban datasets HDF5 | Procedencia engañosa | **Mantenido en `legacy`:** El flujo activo sigue siendo determinista y usa datos controlados. |

## Integración Gemini implementada

1. Flutter envía coordenadas y una pregunta opcional.
2. FastAPI valida los campos y comprueba la cobertura disponible.
3. El servidor construye el contexto a partir de sus propios datos.
4. El SDK oficial google-genai consulta el modelo configurado; la clave permanece en el servidor.
5. Se valida el JSON recibido y se incorpora un aviso controlado por la aplicación.
6. Flutter presenta resumen, observaciones, limitaciones y próximos pasos.

## Qué falta, en orden recomendado

### 1. Conectar el flujo de datos NISAR real al servidor principal
Aunque las credenciales de Earthdata ya están configuradas, el servidor `main.py` actual sigue usando los datos simulados de `data_service.py`. Es necesario migrar la lógica del prototipo (`legacy/nisar_prototype.py`) al servidor principal para que:
- Descargue los productos satelitales reales de la zona de Guatemala.
- Lea correctamente las rutas y estructuras HDF5.
- Convierta la fase a desplazamiento con las unidades correctas.
- Reemplace los datos de prueba con las observaciones satelitales reales.

### 2. Validar interpretación y clasificación
La regla original infería flujo glaciar únicamente con coherencia y movimiento. Hace falta revisar las reglas con especialistas, geometría de observación, contexto del terreno, incertidumbre y datos de referencia antes de mostrar alertas reales.

### 3. Calcular indicadores de población
El área crítica ya se calcula, pero la población afectada requiere una fuente de datos censales y un cruce espacial reproducible.

### 4. Optimización Global (Escalabilidad)
Para procesar datos a nivel mundial, la descarga directa no es viable. Se debe implementar lectura desde *Earthdata Cloud (AWS S3)* usando `xarray` para leer solo los píxeles solicitados (Subsetting).

### 5. Preparar servicio para usuarios
Añadir autenticación, autorización, cuotas por usuario, control de concurrencia, base de datos/caché, HTTPS y despliegue en la nube.

## Validación realizada

- Pruebas de servidor aprobadas: contratos, procedencia, validación, cobertura, SDK, fallos de red, cuota, autenticación, respuestas inválidas, tiempo de espera y CORS.
- Autenticación y lectura de modelo de Gemini aprobadas.
- Solicitud real al endpoint de análisis aprobada con gemini-3.5-flash-lite y salida estructurada en español.