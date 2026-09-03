"""HTTP API: health probes, a demo endpoint and a CPU-bound endpoint for autoscaling demos."""

import hashlib
import os
import random
import socket
import time

from fastapi import FastAPI, HTTPException, Query

from status_api import __version__
from status_api.metrics import install_metrics

APP_VERSION = os.getenv("APP_VERSION", __version__)
# Share of /api/* requests that fail with HTTP 500. Used to trigger the error-rate alert on purpose.
FAILURE_RATE = float(os.getenv("FAILURE_RATE", "0"))

QUOTES = [
    "Automate the boring parts.",
    "If it hurts, do it more often.",
    "You build it, you run it.",
    "Cattle, not pets.",
    "Everything fails, all the time.",
]

app = FastAPI(title="status-api", version=APP_VERSION)
install_metrics(app, APP_VERSION)


def _maybe_fail() -> None:
    if FAILURE_RATE > 0 and random.random() < FAILURE_RATE:
        raise HTTPException(status_code=500, detail="Injected failure (FAILURE_RATE)")


@app.get("/")
def root() -> dict:
    return {"service": "status-api", "version": APP_VERSION, "pod": socket.gethostname()}


@app.get("/healthz")
def healthz() -> dict:
    """Liveness: the process is up."""
    return {"status": "ok"}


@app.get("/readyz")
def readyz() -> dict:
    """Readiness: the service can accept traffic (no external dependencies in this demo)."""
    return {"status": "ready"}


@app.get("/api/quote")
def quote() -> dict:
    _maybe_fail()
    return {"quote": random.choice(QUOTES), "pod": socket.gethostname()}


@app.get("/api/work")
def work(ms: int = Query(default=100, ge=1, le=2000)) -> dict:
    """Burn CPU for roughly `ms` milliseconds so the HPA has something to scale on."""
    _maybe_fail()
    deadline = time.perf_counter() + ms / 1000
    digest = b"seed"
    rounds = 0
    while time.perf_counter() < deadline:
        digest = hashlib.sha256(digest).digest()
        rounds += 1
    return {"rounds": rounds, "pod": socket.gethostname()}
