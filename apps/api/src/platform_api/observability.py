from __future__ import annotations

import json
import logging
import sys
import time
from collections.abc import Awaitable, Callable

from prometheus_client import Counter, Gauge, Histogram
from starlette.requests import Request
from starlette.responses import Response

# Buckets cobrindo o objetivo de latência (300 ms) com resolução em volta dele.
LATENCY_BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 0.75, 1.0, 2.5, 5.0)

HTTP_REQUESTS = Counter(
    "http_requests_total",
    "Total de requisições HTTP processadas.",
    ["method", "route", "status"],
)
HTTP_LATENCY = Histogram(
    "http_request_duration_seconds",
    "Duração das requisições HTTP.",
    ["method", "route"],
    buckets=LATENCY_BUCKETS,
)
HTTP_IN_FLIGHT = Gauge("http_requests_in_flight", "Requisições em andamento.")
APP_INFO = Gauge("app_info", "Metadados da aplicação.", ["version"])

UNMATCHED_ROUTE = "unmatched"


def route_template(request: Request) -> str:
    """Usa o template da rota (/api/items/{item_id}) para manter a cardinalidade baixa."""
    route = request.scope.get("route")
    return getattr(route, "path", UNMATCHED_ROUTE)


async def metrics_middleware(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    if request.url.path == "/metrics":
        return await call_next(request)

    start = time.perf_counter()
    status = 500
    HTTP_IN_FLIGHT.inc()
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        HTTP_IN_FLIGHT.dec()
        elapsed = time.perf_counter() - start
        route = route_template(request)
        HTTP_REQUESTS.labels(request.method, route, str(status)).inc()
        HTTP_LATENCY.labels(request.method, route).observe(elapsed)
        if route not in ("/healthz", "/readyz"):
            logging.getLogger("access").info(
                "request",
                extra={
                    "method": request.method,
                    "route": route,
                    "status": status,
                    "duration_ms": round(elapsed * 1000, 2),
                },
            )


class JsonFormatter(logging.Formatter):
    _std = set(logging.makeLogRecord({}).__dict__) | {"message", "asctime"}

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname.lower(),
            "logger": record.name,
            "msg": record.getMessage(),
        }
        payload.update({k: v for k, v in record.__dict__.items() if k not in self._std})
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


def configure_logging(level: str) -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level.upper())
    for noisy in ("uvicorn.access",):
        logging.getLogger(noisy).disabled = True
