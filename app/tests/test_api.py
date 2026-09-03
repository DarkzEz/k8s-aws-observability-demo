import pytest
from fastapi.testclient import TestClient

from status_api import main
from status_api.main import app

client = TestClient(app)


def test_root_returns_service_info():
    body = client.get("/").json()
    assert body["service"] == "status-api"
    assert "version" in body and "pod" in body


@pytest.mark.parametrize("path", ["/healthz", "/readyz"])
def test_probes_return_200(path):
    assert client.get(path).status_code == 200


def test_quote_returns_known_quote():
    body = client.get("/api/quote").json()
    assert body["quote"] in main.QUOTES


def test_work_burns_cpu_and_validates_input():
    assert client.get("/api/work", params={"ms": 5}).json()["rounds"] > 0
    assert client.get("/api/work", params={"ms": 0}).status_code == 422
    assert client.get("/api/work", params={"ms": 5000}).status_code == 422


def test_failure_injection(monkeypatch):
    monkeypatch.setattr(main, "FAILURE_RATE", 1.0)
    assert client.get("/api/quote").status_code == 500


def test_metrics_use_route_templates_and_skip_probes():
    client.get("/api/quote")
    client.get("/healthz")
    client.get("/does-not-exist")
    text = client.get("/metrics").text

    assert 'http_requests_total{method="GET",route="/api/quote",status="200"}' in text
    assert 'route="unmatched",status="404"' in text
    assert 'route="/healthz"' not in text
    assert "http_request_duration_seconds_bucket" in text
    assert "app_info{" in text
