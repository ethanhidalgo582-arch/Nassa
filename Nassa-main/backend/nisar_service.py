# nisar_service.py
import os
from pathlib import Path
from dotenv import load_dotenv
import h5py
import numpy as np
import earthaccess

# Cargar el archivo .env forzando la ruta exacta
env_path = Path(__file__).resolve().parent / ".env"
load_dotenv(dotenv_path=env_path, override=True)

# DIAGNÓSTICO: Imprimir en la terminal si las credenciales se leyeron
_user = os.getenv("EARTHDATA_USERNAME")
_pass = os.getenv("EARTHDATA_PASSWORD")
print("\n" + "="*50)
print("🔍 DIAGNÓSTICO DE CREDENCIALES EARTHDATA")
print(f"Ruta del archivo .env buscado: {env_path}")
print(f"¿Existe el archivo .env?: {env_path.exists()}")
print(f"Usuario cargado: {'SÍ (' + _user[:3] + '***)' if _user else 'NO'}")
print(f"Contraseña cargada: {'SÍ' if _pass else 'NO'}")
print("="*50 + "\n")

DEMO_BOUNDS = (-90.55, 14.60, -90.45, 14.68)  # west, south, east, north


class NisarDataError(Exception):
    """Se lanza cuando no se pueden obtener o procesar datos reales de NISAR."""
    pass


def descargar_gunw_real():
    try:
        print("\n⏳ Iniciando sesión en Earthdata...")
        auth = earthaccess.login(strategy="environment")
        if not auth.authenticated:
            raise NisarDataError("Credenciales Earthdata inválidas.")
    except Exception as e:
        raise NisarDataError(f"Error al iniciar sesión: {str(e)}")

    try:
        print("🔍 Buscando imágenes NISAR para Guatemala entre 2026-01-01 y 2026-12-31...")
        results = earthaccess.search_data(
            short_name="NISAR_L2_GUNW_PROVISIONAL_V1",
            bounding_box=DEMO_BOUNDS,
            temporal=("2026-01-01", "2026-12-31"),
            count=5,
        )
    except Exception as e:
        raise NisarDataError(f"Error al buscar en la NASA: {str(e)}")
        
    if not results:
        raise NisarDataError("No hay productos GUNW para esta zona/fecha. La NASA aún no tiene imágenes de 2026 para Guatemala.")

    try:
        print(f"⬇️ ¡Imagen encontrada! Descargando archivo (esto puede tardar varios minutos)...")
        # Añadimos un timeout implícito en la descarga para que no se congele
        files = earthaccess.download(results[0], local_path="./data/nisar")
    except Exception as e:
        raise NisarDataError(f"Error al descargar: {str(e)}")

    if not files:
        raise NisarDataError("La descarga falló o se quedó sin tiempo de espera.")
    
    print(f"✅ Archivo descargado con éxito: {files[0]}")
    return files[0]


def leer_gunw(ruta_h5):
    """
    Lee coherencia, fase desenrollada y máscara de componentes conectados
    desde un archivo GUNW de NISAR.
    """
    with h5py.File(ruta_h5, "r") as f:
        base = "/science/LSAR/GUNW/grids/frequencyA/unwrappedInterferogram"

        # Detectar la polarización disponible (normalmente HH o VV)
        pol = "HH"
        if f"{base}/HH" not in f:
            if f"{base}/VV" in f:
                pol = "VV"
            else:
                raise NisarDataError("No se encontró grupo de polarización HH ni VV.")

        pol_base = f"{base}/{pol}"

        coh_path = f"{pol_base}/coherenceMagnitude"
        if coh_path not in f:
            coh_path = f"{pol_base}/coherence"
        if coh_path not in f:
            raise NisarDataError("No se encontró la capa de coherencia.")

        phase_path = f"{pol_base}/unwrappedPhase"
        if phase_path not in f:
            raise NisarDataError("No se encontró la capa de fase desenrollada.")

        coherencia = f[coh_path][()]
        fase = f[phase_path][()]

        cc_path = f"{pol_base}/connectedComponents"
        if cc_path in f:
            cc = f[cc_path][()]
            valido = cc <= 254  # Valores > 254 indican píxeles inválidos en NISAR
        else:
            valido = np.ones_like(fase, dtype=bool)

    return coherencia, fase, valido


def fase_a_desplazamiento_mm(fase_rad, banda="L"):
    """
    Convierte fase desenrollada (radianes) a desplazamiento LOS (mm).
    Banda L de NISAR tiene longitud de onda de 24 cm.
    """
    lambda_m = {"L": 0.24, "S": 0.094}[banda]
    return -(lambda_m / (4 * np.pi)) * fase_rad * 1000


def procesar_gunw(ruta_h5, classify_change):
    """
    Ejecuta el flujo completo de lectura, conversión y clasificación para un GUNW.
    Devuelve un diccionario con coherencia media, desplazamiento medio y categorías.
    """
    coh, fase, valido = leer_gunw(ruta_h5)
    disp = fase_a_desplazamiento_mm(fase)

    # Máscara de píxeles válidos: componentes conectados + coherencia mínima + valores finitos
    mascara = valido & (coh > 0.2) & np.isfinite(disp)
    if mascara.sum() == 0:
        raise NisarDataError("No hay píxeles válidos en este GUNW.")

    mean_coh = float(np.mean(coh[mascara]))
    mean_disp = float(np.mean(disp[mascara]))

    categorias = classify_change(mean_coh, mean_disp)

    return {
        "mean_coherence": round(mean_coh, 3),
        "mean_displacement_mm": round(mean_disp, 2),
        "categories": categorias,
        "source": "NISAR L2 GUNW (real)",
        "is_simulated": False,
    }