# --- build stage: install dependencies into an isolated virtualenv ---
FROM python:3.12-slim AS build

ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /src
COPY pyproject.toml ./
COPY src ./src
RUN pip install .

# --- runtime stage: only the virtualenv, no build tooling, non-root user ---
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PATH="/opt/venv/bin:$PATH"
COPY --from=build /opt/venv /opt/venv
RUN useradd --system --uid 10001 --no-create-home app

USER 10001
EXPOSE 8000
CMD ["uvicorn", "status_api.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
