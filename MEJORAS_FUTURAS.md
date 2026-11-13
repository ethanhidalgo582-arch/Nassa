# Hoja de Ruta y Mejoras Futuras (Roadmap)
**Proyecto:** NISAR App - Monitoreo Satelital con IA
**Estado actual:** Versión funcional (MVP) con integración a Earthdata, OpenStreetMap, Gemini y sistema de respaldo local (JSON).

Este documento detalla los aspectos técnicos y de experiencia de usuario (UX) que se recomiendan implementar en las próximas versiones para llevar la aplicación a un nivel de producción real.

---

## 1. Mejoras de Experiencia de Usuario (UX) y Comunicación

El objetivo principal es que la aplicación no solo sea para científicos o ingenieros, sino para cualquier persona interesada en el impacto ambiental.

*   **Doble Nivel de Información (Técnico y Ciudadano):**
    *   **Vista Técnica (Actual):** Mostrar los datos crudos como milímetros (mm), coherencia, percentiles y fase radar LOS. Dirigido a investigadores.
    *   **Vista Ciudadana (Nueva):** Agregar una pestaña o sección que traduzca esos datos a un lenguaje cotidiano. Ejemplo: En lugar de decir *"Desplazamiento LOS de -120 mm"*, mostrar: *"El suelo de esta zona se ha hundido el equivalente al grosor de un teléfono celular en el último año"*.
*   **Semáforo de Riesgo Visual:** Implementar un indicador visual rápido (Verde = Estable, Amarillo = Precaución, Rojo = Crítico) basado en los umbrales de los datos satelitales, para que el usuario entienda la gravedad de un vistazo.
*   **Exportación de Reportes:** Añadir un botón para que el usuario pueda descargar el análisis de Gemini y las gráficas en un archivo PDF, ideal para compartir o presentar en investigaciones.

## 2. Optimización de Rendimiento y Conexión Satelital

Actualmente, la app es robusta gracias al sistema de respaldo JSON, pero se debe mejorar la velocidad cuando los servidores de la NASA están activos.

*   **Implementación de Caché (Base de Datos):** Cuando el backend descargue un archivo `.h5` real y lo procese, guardar el resultado en una base de datos local (como SQLite o Redis). Si otro usuario pide la misma zona y fechas, el servidor responderá en milisegundos sin volver a consultar a la NASA.
*   **Descarga Asíncrona en Segundo Plano:** Mover la descarga de archivos `.h5` a un "trabajo en segundo plano" (Background Tasks). Así, el usuario puede seguir navegando en el mapa mientras el servidor descarga el satélite, y notificarle cuando esté listo.
*   **Conexión Directa a la Nube (AWS S3):** En lugar de descargar el archivo `.h5` completo (que puede pesar gigabytes), usar librerías como `xarray` o `h5py` conectadas a la nube de la NASA (Earthdata Cloud) para leer **solo el pedacito de píxeles** que el usuario está viendo en el mapa. Esto reduce el tiempo de respuesta de minutos a segundos.

## 3. Sugerencias Adicionales (Nuevas Funcionalidades)

*   **Historial de Búsquedas y Favoritos:** Permitir que el usuario guarde sus zonas de interés (Ej: "Mi ciudad", "Glaciar favorito") para no tener que dibujar el polígono cada vez que entra.
*   **Alertas Automatizadas (Notificaciones):** Si un glaciar o una zona de hundimiento supera un umbral crítico en los datos de NISAR, enviar un correo electrónico o notificación push al usuario.
*   **Integración de Datos de Población:** Cruzar los datos satelitales con bases de datos de densidad poblacional (como las de la NASA SEDAC). Así, si una zona se inunda, la app podría decir: *"Este hundimiento afecta a una zona donde viven aproximadamente 50,000 personas"*.
*   **Modelo 3D del Terreno:** Para el módulo de glaciares, agregar una vista 3D (usando Three.js o Flutter 3D) para visualizar la topografía del hielo y cómo cambia con el tiempo.

## 4. Notas Técnicas de Mantenimiento
*   **Validación Científica:** Consultar con geólogos o glaciólogos para validar que la conversión de fase radar a movimiento real está alineada con los estándares de la NASA.
*   **Migración a la Nube:** Para que la app sea pública, el backend (FastAPI) debe desplegarse en un servicio como Render, Railway o AWS, y el frontend (Flutter) en Vercel o Firebase Hosting.
*   **Seguridad:** Rotar las API Keys periódicamente y manejar la autenticación de usuarios si se planea lanzar al público.

---
*Documento generado por el equipo de desarrollo de NISAR App.*