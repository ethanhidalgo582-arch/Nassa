import h5py
import numpy as np
import json
from pathlib import Path

def extraer_datos_ligeros(ruta_h5):
    print(f"Procesando {ruta_h5}...")
    try:
        with h5py.File(ruta_h5, "r") as f:
            grid = f["/science/LSAR/GUNW/grids/frequencyA"]
            base = grid["unwrappedInterferogram"]
            pol = next((n for n in ("HH", "VV") if n in base), None)
            if not pol: return
            
            group = base[pol]
            
            # Leemos solo 1 de cada 100 píxeles (Muestreo)
            phase = group["unwrappedPhase"][::100, ::100].tolist()
            coh = group["coherenceMagnitude" if "coherenceMagnitude" in group else "coherence"][::100, ::100].tolist()
            x = grid["xCoordinates"][::100].tolist()
            y = grid["yCoordinates"][::100].tolist()
            
            datos = {
                "x": x,
                "y": y,
                "phase": phase,
                "coherence": coh
            }
            
            ruta_json = ruta_h5.replace(".h5", "_ligero.json")
            with open(ruta_json, "w") as f_json:
                json.dump(datos, f_json)
            print(f"✅ Guardado en {ruta_json}")
    except Exception as e:
        print(f"Error procesando {ruta_h5}: {e}")

if __name__ == "__main__":
    carpeta = Path(__file__).parent / "data" / "nisar"
    for archivo in carpeta.glob("*.h5"):
        extraer_datos_ligeros(str(archivo))