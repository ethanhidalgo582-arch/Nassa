# nisar_service.py
import os
import datetime
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

# Fechas de disponibilidad oficial de NISAR PROVISIONAL
# (NISAR lanzó datos PROVISIONAL el 20 de julio de 2026, con datos desde el 17 de junio de 2026)
FECHA_INICIO_NISAR = "2026-06-17"
FECHA_FIN_NISAR = datetime.date.today().isoformat()


class NisarDataError(Exception):
    """Se lanza cuando no se pueden obtener o procesar datos reales de NISAR."""
    pass


def _autenticar_earthdata():
    """Inicia sesión en Earthdata usando las variables de entorno."""
    try:
        auth = earthaccess.login(strategy="environment")
        if not auth.authenticated:
            raise NisarDataError("Credenciales Earthdata inválidas.")
    except Exception as e:
        raise NisarDataError(f"Error al iniciar sesión en Earthdata: {str(e)}")


def buscar_ventana_temporal(bbox, max_resultados=100):
    """
    Busca todos los productos GUNW disponibles en un área y devuelve
    el más antiguo y el más reciente.
    
    bbox: tupla (west, south, east, north)
    """
    _autenticar_earthdata()

    print(f"🔍 Buscando GUNW en el área {bbox} desde {FECHA_INICIO_NISAR} hasta {FECHA_FIN_NISAR}...")
    try:
        results = earthaccess.search_data(
            short_name="NISAR_L2_GUNW_PROVISIONAL_V1",
            bounding_box=bbox,
            temporal=(FECHA_INICIO_NISAR, FECHA_FIN_NISAR),
            count=max_resultados,
        )
    except Exception as e:
        raise NisarDataError(f"Error al buscar en la NASA: {str(e)}")

    if not results:
        raise NisarDataError(
            f"No hay productos GUNW para esta zona entre {FECHA_INICIO_NISAR} y {FECHA_FIN_NISAR}."
        )

    # Ordenar por fecha de adquisición (los metadatos de earthaccess lo tienen en 'umm' o similar)
    def extraer_fecha(granule):
        try:
            # Intentar sacar la fecha de inicio de la adquisición
            temporal = granule["umm"]["TemporalExtent"]["RangeDateTime"]
            return temporal.get("BeginningDateTime", "")
        except KeyError:
            return ""

    results.sort(key=extraer_fecha)

    mas_antiguo = results[0]
    mas_reciente = results[-1]

    print(f"✅ Se encontraron {len(results)} productos.")
    print(f"   - Más antiguo: {extraer_fecha(mas_antiguo)}")
    print(f"   - Más reciente: {extraer_fecha(mas_reciente)}")

    return mas_antiguo, mas_reciente


def descargar_granulo(granule, local_path="./data/nisar"):
    """Descarga un solo granulo GUNW y devuelve la ruta del archivo .h5."""
    Path(local_path).mkdir(parents=True, exist_ok=True)
    try:
        print(f"⬇️ Descargando archivo...")
        files = earthaccess.download(granule, local_path=local_path)
    except Exception as e:
        raise NisarDataError(f"Error al descargar: {str(e)}")

    if not files:
        raise NisarDataError("La descarga falló.")
    print(f"✅ Archivo descargado: {files[0]}")
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


def obtener_comparacion_historica(bbox, classify_change):
    """
    Orquesta el flujo completo: buscar el primero y el último, descargarlos,
    procesarlos y calcular el delta.
    """
    granulo_antiguo, granulo_reciente = buscar_ventana_temporal(bbox)

    print("📥 Procesando el archivo MÁS ANTIGUO...")
    ruta_antigua = descargar_granulo(granulo_antiguo)
    datos_antiguos = procesar_gunw(ruta_antigua, classify_change)

    print("📥 Procesando el archivo MÁS RECIENTE...")
    ruta_reciente = descargar_granulo(granulo_reciente)
    datos_recientes = procesar_gunw(ruta_reciente, classify_change)

    # Calcular delta
    delta_disp = datos_recientes["mean_displacement_mm"] - datos_antiguos["mean_displacement_mm"]
    delta_coh = datos_recientes["mean_coherence"] - datos_antiguos["mean_coherence"]

    # Calcular días transcurridos (si las fechas están en el formato correcto)
    try:
        fecha_a = datetime.datetime.fromisoformat(granulo_antiguo["umm"]["TemporalExtent"]["RangeDateTime"]["BeginningDateTime"].replace("Z", "+00:00"))
        fecha_r = datetime.datetime.fromisoformat(granulo_reciente["umm"]["TemporalExtent"]["RangeDateTime"]["BeginningDateTime"].replace("Z", "+00:00"))
        dias = (fecha_r - fecha_a).days
    except Exception:
        dias = None

    return {
        "old_data": datos_antiguos,
        "new_data": datos_recientes,
        "delta_displacement_mm": round(delta_disp, 2),
        "delta_coherence": round(delta_coh, 3),
        "time_span_days": dias,
        "bbox": bbox,
        "source": "NISAR L2 GUNW (comparación histórica)",
        "is_simulated": False,
    }

# Añadir al final de nisar_service.py

# Definición de regiones con sus bounding boxes (west, south, east, north)
REGIONES_INTERES = {
    "guatemala": (-92.3, 13.7, -88.2, 17.8),
    "polo_norte": (-180.0, 80.0, 180.0, 90.0),
    "polo_sur": (-180.0, -90.0, 180.0, -80.0),
    "everest": (86.8, 27.9, 87.0, 28.1),
    "amazonas": (-73.0, -10.0, -45.0, 5.0),
}

def obtener_comparacion_multiregion(classify_change, regiones=None):
    """
    Procesa la comparación histórica para una lista de regiones.
    Devuelve un diccionario con resultados por región y errores controlados.
    """
    if regiones is None:
        regiones = REGIONES_INTERES

    resultados = {}
    errores = {}

    for nombre, bbox in regiones.items():
        print(f"\n=== Procesando región: {nombre} ===")
        try:
            comparacion = obtener_comparacion_historica(bbox, classify_change)
            resultados[nombre] = comparacion
            print(f"✅ {nombre}: desplazamiento delta = {comparacion['delta_displacement_mm']} mm")
        except NisarDataError as e:
            # Capturamos el error para que una región no rompa las demás
            errores[nombre] = str(e)
            print(f"⚠️ {nombre}: {e}")
        except Exception as e:
            errores[nombre] = f"Error inesperado: {str(e)}"
            print(f"❌ {nombre}: {e}")

    return {
        "regiones": resultados,
        "errores": errores,
        "total_procesadas": len(resultados),
        "total_fallidas": len(errores),
    }