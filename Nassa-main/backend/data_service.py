"""Demostración determinista; todavía no es un procesador de productos NISAR."""

from copy import deepcopy

DEMO_BOUNDS = (-90.55, 14.60, -90.45, 14.68)  # west, south, east, north
DATA_SOURCE = "demo_simulada"
NOTICE = (
    "Datos simulados para probar la aplicación. No son mediciones de NISAR "
    "ni confirman riesgos o desastres reales."
)
_HISTORY = [
    {"date": "2026-05-01", "displacement_mm": -2.1},
    {"date": "2026-06-01", "displacement_mm": -5.4},
    {"date": "2026-07-01", "displacement_mm": -9.0},
    {"date": "2026-08-01", "displacement_mm": -13.2},
    {"date": "2026-09-01", "displacement_mm": -18.0},
    {"date": "2026-10-01", "displacement_mm": -22.9},
]
_CATEGORIES = [{
    "type": "desplazamiento_simulado",
    "severity": "informativa",
    "description": "Ejemplo de desplazamiento LOS negativo; no demuestra hundimiento vertical.",
}]


class OutsideCoverageError(Exception):
    pass


def classified_zones():
    west, south, east, north = DEMO_BOUNDS
    return {
        "type": "FeatureCollection",
        "features": [{
            "type": "Feature",
            "geometry": {"type": "Polygon", "coordinates": [[
                [west, north], [east, north], [east, south], [west, south], [west, north]
            ]]},
            "properties": {
                "categories": deepcopy(_CATEGORIES),
                "mean_coherence": 0.5,
                "mean_displacement_mm": -22.9,
                "source": DATA_SOURCE,
                "is_simulated": True,
                "note": NOTICE,
            },
        }],
    }


def displacement(latitude: float, longitude: float):
    west, south, east, north = DEMO_BOUNDS
    if not (west <= longitude <= east and south <= latitude <= north):
        raise OutsideCoverageError("No hay datos para este punto. Selecciona el polígono de demostración.")
    return {
        "latitude": latitude,
        "longitude": longitude,
        "current_displacement_mm": _HISTORY[-1]["displacement_mm"],
        "mean_coherence": 0.5,
        "unit": "mm",
        "measurement": "LOS simulado; no equivale a desplazamiento vertical",
        "spatial_scope": "La misma serie ilustrativa se usa en todo el polígono, no por píxel.",
        "history": deepcopy(_HISTORY),
        "categories": deepcopy(_CATEGORIES),
        "source": DATA_SOURCE,
        "is_simulated": True,
        "note": NOTICE,
    }


def dashboard_stats():
    return {
        "activeAlerts": None,
        "criticalAreaKm2": None,
        "affectedPopulation": None,
        "lastUpdate": "Demostración: sin monitoreo en tiempo real",
        "source": DATA_SOURCE,
        "is_simulated": True,
        "note": NOTICE,
    }
