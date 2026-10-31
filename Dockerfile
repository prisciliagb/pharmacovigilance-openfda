FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

WORKDIR /app

# Dépendances d'abord : cette couche reste en cache tant que uv.lock ne change pas
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --frozen --no-dev --no-install-project

COPY ingestion/ ingestion/

ENV PYTHONUNBUFFERED=1
CMD ["uv", "run", "--no-sync", "python", "-m", "ingestion.ingest_openfda"]
