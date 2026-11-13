# hydro_service.py
import osmnx as ox
from shapely.geometry import Polygon
import logging

# Configurar osmnx para que no haga demasiadas peticiones y falle rápido si no hay internet
ox.settings.timeout = 10
ox.settings.use_cache = True

def analizar_agua_en_poligono(coordenadas: list[tuple[float, float]]) -> dict:
    """
    Recibe una lista de coordenadas [(lat, lon), (lat, lon), ...]
    Devuelve un dict con las áreas de agua y tierra encontradas.
    """
    try:
        # osmnx espera las coordenadas como (lon, lat) para Polygon
        # y el polígono debe estar cerrado.
        puntos = [(lon, lat) for lat, lon in coordenadas]
        if puntos[0] != puntos[-1]:
            puntos.append(puntos[0])
            
        poligono = Polygon(puntos)
        
        # Buscar cuerpos de agua y ríos dentro del polígono
        tags = {"natural": "water", "waterway": True}
        try:
            agua_gdf = ox.features_from_polygon(poligono, tags=tags)
        except Exception:
            # Si no encuentra nada, devuelve un GeoDataFrame vacío
            agua_gdf = None

        # Calcular áreas (en grados cuadrados primero, luego lo convertimos a porcentaje)
        area_total_poligono = poligono.area
        
        porcentaje_agua = 0.0
        tipos_agua = []

        if agua_gdf is not None and not agua_gdf.empty:
            # Proyectar a un sistema de coordenadas métrico para calcular áreas reales (metros cuadrados)
            agua_gdf_proj = ox.projection.project_gdf(agua_gdf)
            poligono_proj = ox.projection.project_geometry(poligono, crs="EPSG:4326")[0]
            
            # Recortar el agua solo a lo que está dentro del polígono
            agua_recortada = agua_gdf_proj.geometry.intersection(poligono_proj)
            area_agua_m2 = agua_recortada.area.sum()
            area_total_m2 = poligono_proj.area
            
            if area_total_m2 > 0:
                porcentaje_agua = (area_agua_m2 / area_total_m2) * 100
                
            # Extraer qué tipos de agua son
            if 'waterway' in agua_gdf.columns:
                tipos_agua.extend(agua_gdf['waterway'].dropna().unique().tolist())
            if 'natural' in agua_gdf.columns:
                tipos_agua.extend(agua_gdf['natural'].dropna().unique().tolist())
            
        porcentaje_tierra = 100.0 - porcentaje_agua

        return {
            "porcentaje_agua": round(porcentaje_agua, 2),
            "porcentaje_tierra": round(porcentaje_tierra, 2),
            "tipos_agua": list(set(tipos_agua)),
            "tiene_agua": porcentaje_agua > 0.5  # Si es más del 0.5%, consideramos que hay agua
        }

    except Exception as e:
        logging.error(f"Error consultando OSM: {e}")
        return {
            "porcentaje_agua": None,
            "porcentaje_tierra": None,
            "tipos_agua": [],
            "tiene_agua": False,
            "error": "No se pudo consultar el mapa base."
        }