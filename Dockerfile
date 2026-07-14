FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PORT=6050

# NudeNet pulls in onnxruntime + opencv, which need these shared libs at runtime.
# curl is used by the container HEALTHCHECK below.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 libglib2.0-0 curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements first so the (slow) dependency layer is cached across code changes.
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

# Non-root, with a writable HOME for the NudeNet model cache it downloads on first use.
RUN useradd --create-home --uid 10001 appuser && chown -R appuser:appuser /app
USER appuser
ENV HOME=/home/appuser

EXPOSE 6050

HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
    CMD curl -fsS "http://localhost:${PORT}/health" || exit 1

# init_db creates/migrates tables, then the worker long-polls + serves /key & /health.
CMD ["sh", "-c", "python init_db.py && python -m spam_bot.main"]
