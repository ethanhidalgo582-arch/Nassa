from pathlib import Path

from fastapi.staticfiles import StaticFiles

from main import app


web_directory = Path("/app/web")
app.router.routes[:] = [
    route
    for route in app.router.routes
    if not (getattr(route, "path", None) == "/" and "GET" in getattr(route, "methods", set()))
]
app.mount("/", StaticFiles(directory=web_directory, html=True), name="frontend")
