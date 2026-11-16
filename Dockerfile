FROM ghcr.io/cirruslabs/flutter:stable AS frontend
WORKDIR /app/mobile
COPY mobile/pubspec.yaml mobile/pubspec.lock ./
RUN flutter pub get
COPY mobile/ ./
RUN flutter build web --release --dart-define=API_BASE_URL=/api/v1

FROM python:3.14-slim
ENV PYTHONUNBUFFERED=1
ENV WEB_DIR=/app/web
WORKDIR /app/backend
COPY backend/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/ ./
COPY --from=frontend /app/mobile/build/web /app/web
CMD ["sh", "-c", "exec uvicorn main:app --host 0.0.0.0 --port ${PORT:-10000}"]
