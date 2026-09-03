"""Prometheus metrics and the middleware that records them."""

import time

from fastapi import FastAPI, Request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest
from starlette.responses import Response

REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP requests.",
    ["method", "route", "status"],
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds.",
    ["method", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)
IN_FLIGHT = Gauge("http_requests_in_flight", "Requests currently being served.")
APP_INFO = Gauge("app_info", "Static application info.", ["version"])

# Probes and the metrics endpoint itself are excluded to keep dashboards clean.
EXCLUDED_ROUTES = {"/metrics", "/healthz", "/readyz"}


def _route_template(request: Request) -> str:
    """Use the route pattern (/items/{id}), never the raw path, to keep label cardinality low."""
    route = request.scope.get("route")
    return getattr(route, "path", "unmatched")


def install_metrics(app: FastAPI, version: str) -> None:
    APP_INFO.labels(version=version).set(1)

    @app.middleware("http")
    async def record_metrics(request: Request, call_next):
        start = time.perf_counter()
        IN_FLIGHT.inc()
        status = 500
        try:
            response = await call_next(request)
            status = response.status_code
            return response
        finally:
            IN_FLIGHT.dec()
            route = _route_template(request)
            if route not in EXCLUDED_ROUTES:
                REQUESTS.labels(request.method, route, str(status)).inc()
                LATENCY.labels(request.method, route).observe(time.perf_counter() - start)

    @app.get("/metrics", include_in_schema=False)
    def metrics() -> Response:
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
