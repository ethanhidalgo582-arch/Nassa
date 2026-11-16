# data_service.py
import os
from copy import deepcopy
import nisar_service

DEMO_BOUNDS = (-90.55, 14.60, -90.45, 14.68)  # west, south, east, north
DATA_SOURCE = "demo_simulada"  # Solo se usa como valor de respaldo
NOTICE = (
    "Análisis generado a partir de datos satelitales. "
    "Requiere validación técnica."
)


class OutsideCoverageError(Exception):
    pass


def classify_change(coherence, displacement_mm, backscatter=None):
    """
    Clasifica cambios superficiales según coherencia y desplazamiento.
    (Código original trasladado desde nisar_prototype.py)
    """
    categories = []

    if coherence < 0.3 and abs(displacement_mm) > 10:
        categories.append({
            "type": "deslizamiento",
            "severity": "alta" if abs(displacement_mm) > 50 else "media",
            "description": "Pérdida de coherencia con desplazamiento significativo, posible deslizamiento o colapso superficial"
        })

    if displacement_mm < -5:
        categories.append({
            "type": "subsidencia_suelo",
            "severity": "alta" if displacement_mm < -30 else "media",
            "description": f"Hundimiento del terreno ({displacement_mm:.1f} mm en LOS)"
        })

    if displacement_mm > 5:
        categories.append({
            "type": "levantamiento_suelo",
            "severity": "alta" if displacement_mm > 30 else "media",
            "description": f"Levantamiento del terreno ({displacement_mm:.1f} mm en LOS)"
        })

    if backscatter is not None and backscatter < -15:
        categories.append({
            "type": "cuerpo_agua",
            "severity": "informativa",
            "description": "Retrodispersión baja, probable superficie de agua (río, inundación)"
        })

    if 0.3 <= coherence < 0.7 and abs(displacement_mm) > 20:
        categories.append({
            "type": "flujo_glaciar",
            "severity": "media",
            "description": "Desplazamiento con coherencia moderada, posible flujo de glaciar o movimiento de masa lento"
        })

    if not categories:
        categories.append({
            "type": "estable",
            "severity": "baja",
            "description": "Sin cambios significativos detectados"
        })

    return categories


_real_cache = {"result": None}


def _cargar_datos_reales():
    """
    Carga y cachea datos reales de NISAR.
    Si USE_REAL_NISAR=0, lanza una excepción para que los tests no accedan a la red.
    """
    if os.getenv("USE_REAL_NISAR", "1") != "1":
        raise OutsideCoverageError("Modo test: datos reales deshabilitados.")

    if _real_cache["result"] is not None:
        return _real_cache["result"]

    try:
        ruta = nisar_service.descargar_gunw_real()
        resultado = nisar_service.procesar_gunw(ruta, classify_change)
    except nisar_service.NisarDataError as exc:
        raise OutsideCoverageError(str(exc)) from exc

    _real_cache["result"] = resultado
    return resultado


def displacement(latitude: float, longitude: float):
    west, south, east, north = DEMO_BOUNDS
    if not (west <= longitude <= east and south <= latitude <= north):
        raise OutsideCoverageError(
            "No hay datos para este punto. Selecciona el polígono de demostración."
        )

    real = _cargar_datos_reales()
    return {
        "latitude": latitude,
        "longitude": longitude,
        "current_displacement_mm": real["mean_displacement_mm"],
        "mean_coherence": real["mean_coherence"],
        "unit": "mm",
        "measurement": "LOS derivado de fase desenrollada NISAR",
        "spatial_scope": "Media del polígono, no por píxel.",
        "history": [],
        "categories": deepcopy(real["categories"]),
        "source": real["source"],
        "is_simulated": False,
        "note": "Producto NISAR L2 GUNW real.",
    }


def classified_zones():
    real = _cargar_datos_reales()
    west, south, east, north = DEMO_BOUNDS
    return {
        "type": "FeatureCollection",
        "features": [{
            "type": "Feature",
            "geometry": {"type": "Polygon", "coordinates": [[
                [west, north], [east, north], [east, south], [west, south], [west, north]
            ]]},
            "properties": {
                "categories": deepcopy(real["categories"]),
                "mean_coherence": real["mean_coherence"],
                "mean_displacement_mm": real["mean_displacement_mm"],
                "source": real["source"],
                "is_simulated": False,
                "note": "Producto NISAR L2 GUNW real.",
            },
        }],
    }


def dashboard_stats():
    real = _cargar_datos_reales()
    return {
        "activeAlerts": None,
        "criticalAreaKm2": None,
        "affectedPopulation": None,
        "lastUpdate": "NISAR GUNW real",
        "source": real["source"],
        "is_simulated": False,
        "note": "Estadísticas basadas en el producto GUNW descargado.",
    }