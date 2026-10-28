# Revisión de la app y trabajo pendiente

Revisión del ZIP Nassa-main.zip, 27 de octubre de 2026. Se trabajó en una copia extraída; el ZIP original no se modificó.

## Lo que ya tenía

- Flutter: mapa de OpenStreetMap, polígonos, selección de punto, gráfica y panel de estadísticas.
- FastAPI: endpoints para zonas clasificadas, desplazamiento y estadísticas.
- Prototipo para buscar y descargar un producto NISAR mediante Earthdata.
- Reglas heurísticas de clasificación por coherencia y desplazamiento.

Es una base de demostración, sin flujo de IA previo, cuentas de usuario, almacenamiento persistente o despliegue configurado.

## Hallazgos y tratamiento

| Hallazgo en el ZIP | Consecuencia | Tratamiento en esta entrega |
|---|---|---|
| Flutter pedía disaster-zones; FastAPI ofrecía classified-zones | El mapa no obtenía los polígonos | Ruta corregida y alias conservado |
| URL fija localhost | Android no llegaba al servidor del equipo | URL configurable y valor por defecto para el emulador |
| requirements.txt solo contenía fastapi y uvicorn, aunque main importaba earthaccess, h5py y numpy | Una instalación limpia no arrancaba | Demo desacoplada; dependencias del flujo activo declaradas y versiones instaladas registradas |
| Login y descarga de NASA al arrancar | Inicio dependiente de credenciales, red y archivos grandes | Prototipo preservado aparte; arranque local determinista |
| Valores aleatorios si faltaban datasets HDF5, manteniendo etiqueta de muestra real | Procedencia engañosa | El flujo activo solo devuelve datos identificados como simulados |
| Mismo resultado para cualquier latitud/longitud | Apariencia de cobertura global | Validación de coordenadas y 404 fuera del polígono |
| Área y población constantes | Indicadores sin cálculo real | Ahora null / “Sin calcular”; alertas “Sin validar” |
| Fase leída sin conversión efectiva a milímetros | Unidades no validadas | No se usa el prototipo para alimentar Gemini |
| Geometría fija en Guatemala aunque el producto se buscaba sin filtro geográfico | Producto y mapa podían no coincidir | Cobertura explícita de demostración; integración real pendiente |
| Serie temporal fabricada a partir de un solo producto | No es una historia observada | Serie etiquetada como simulada |
| Test Flutter de un contador y clase MyApp inexistente | Prueba ajena a la app y que no compila | Sustituida por pruebas del panel de IA y del servicio |
| Sin timeout, manejo visible de todos los errores ni protección frente a respuestas atrasadas | Esperas o resultados de otro punto | Timeouts, errores visibles y descarte de respuestas anteriores |
| Permiso de Internet solo en modos de desarrollo Android | Conectividad incompleta en release | Permiso principal; HTTP limitado a debug/profile |

El archivo original permanece en `backend/legacy/nisar_prototype.py`. No se eliminó su implementación experimental, pero dejó de ser el servidor activo.

## Integración Gemini implementada

1. Flutter envía coordenadas y una pregunta opcional.
2. FastAPI valida los campos y comprueba la cobertura disponible.
3. El servidor construye el contexto a partir de sus propios datos.
4. El SDK oficial google-genai consulta el modelo configurado; la clave permanece en el servidor.
5. Se valida el JSON recibido y se incorpora un aviso de simulación controlado por la aplicación.
6. Flutter presenta resumen, observaciones, limitaciones y próximos pasos.

La IA explica los datos. No descarga productos satelitales, no convierte fase a desplazamiento ni calcula por sí sola exposición o riesgo. Las instrucciones al modelo reducen respuestas infundadas, pero no son una garantía de exactitud científica.

## Qué falta, en orden recomendado

### 1. Completar la prueba móvil

Instalar Flutter compatible, ejecutar flutter analyze y flutter test, comprobar el mapa y el panel en navegador y Android, y realizar una prueba con servidor HTTPS en iOS. La conexión real del servidor a Gemini sí se comprobó; el cliente móvil no se compiló en este equipo.

### 2. Construir el proveedor de datos NISAR real

- Configurar Earthdata de manera no interactiva.
- Seleccionar productos por área, fechas, cobertura, órbita y calidad.
- Confirmar rutas y estructura HDF5 de la versión del producto elegida.
- Leer georreferenciación, sistema de coordenadas, máscaras y valores inválidos.
- Convertir fase a desplazamiento con longitud de onda, unidades y convención de signo correctas.
- Mantener trazabilidad del producto, fechas, procesamiento y calidad.
- Consultar el dato del píxel o zona realmente seleccionada.
- Construir series temporales desde observaciones compatibles y múltiples fechas.
- Procesar y almacenar resultados fuera del arranque del servidor.

### 3. Validar interpretación y clasificación

La regla original infería flujo glaciar únicamente con coherencia y movimiento, sin información de glaciar o altitud. También interpretaba el signo LOS como levantamiento o hundimiento vertical. Hace falta revisar las reglas con especialistas, geometría de observación, contexto del terreno, incertidumbre y datos de referencia antes de mostrar alertas reales.

### 4. Calcular indicadores

Definir qué constituye una alerta y calcular superficie a partir de geometría válida. La población afectada requiere una fuente de población y un cruce espacial reproducible. No deben recuperarse los números constantes del prototipo como métricas reales.

### 5. Preparar servicio para usuarios

Añadir autenticación, autorización, cuotas por usuario, control de concurrencia, presupuesto y alertas de consumo, registro de errores sin secretos, base de datos/caché, trabajos de procesamiento, HTTPS y despliegue. Definir política de uso de coordenadas y preguntas enviadas al proveedor de IA.

## Validación realizada

- 30 pruebas de servidor aprobadas: contratos, procedencia, validación, cobertura, SDK, fallos de red, cuota, autenticación, respuestas inválidas, tiempo de espera y CORS.
- Comprobación de importación y sintaxis Python aprobada.
- Autenticación y lectura de modelo de Gemini aprobadas.
- Solicitud real al endpoint de análisis aprobada con gemini-3.5-flash-lite y salida estructurada en español.
- gemini-3.8-flash devolvió 503 por alta demanda; por ello se configuró Flash-Lite.
- Flutter: pruebas escritas, pendientes de ejecución por ausencia del SDK.
- No se probó ni se anuncia funcionamiento científico del pipeline NISAR original.

