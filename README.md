# NISAR App — entrega del 12 de noviembre
Esta versión conserva Flutter y FastAPI e incorpora Dashboard, Bosques, Hundimiento y Desplazamiento.
Lee Detalle_Implementacion_NISAR.md para instalar y ejecutar, Conexion_Frontend_Backend_NISAR.md para los contratos y VALIDACION.md para los límites de las pruebas.

## Arranque
1. Python 3.12 y Flutter instalado; ejecutar Instalar.ps1 o los comandos manuales del detalle.
2. Configurar backend/.env con credenciales propias; Gemini es opcional.
3. Ejecutar Iniciar.ps1. También hay comandos para dos terminales.
4. Seleccionar área y fechas, después Calcular métricas.

Bosques compara cartografía OSM. Desplazamiento procesa fase GUNW del par exacto. Hundimiento muestra únicamente una proyección condicionada, no una medición vertical validada.
No contiene credenciales, datos satelitales descargados ni resultados reales precargados.
No utilizar el requirements-lock histórico como receta de instalación; la receta actual es backend/requirements.txt.
Los contratos antiguos de análisis se migran a /api/v1/metrics y /api/v1/ai/interpret.

