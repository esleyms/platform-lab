import hmac
import logging
import random
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Annotated

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request, status
from fastapi.responses import JSONResponse, PlainTextResponse
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, Field

from .config import Settings, get_settings
from .observability import APP_INFO, configure_logging, metrics_middleware
from .repository import InMemoryRepository, ItemRepository, PostgresRepository

log = logging.getLogger("platform_api")


class ItemIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=1000)


class ItemOut(BaseModel):
    id: int
    name: str
    description: str | None
    created_at: datetime


def build_repository(settings: Settings) -> ItemRepository:
    if settings.database_url:
        return PostgresRepository(
            settings.database_url,
            settings.db_pool_min,
            settings.db_pool_max,
            settings.db_timeout_seconds,
        )
    log.warning("APP_DATABASE_URL não definido; usando repositório em memória")
    return InMemoryRepository()


def create_app(
    settings: Settings | None = None, repository: ItemRepository | None = None
) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        app.state.repo = repository or build_repository(settings)
        APP_INFO.labels(settings.version).set(1)
        log.info("startup", extra={"version": settings.version})
        yield
        app.state.repo.close()
        log.info("shutdown")

    app = FastAPI(title="platform-lab api", version=settings.version, lifespan=lifespan)
    app.middleware("http")(metrics_middleware)

    def repo(request: Request) -> ItemRepository:
        return request.app.state.repo

    Repo = Annotated[ItemRepository, Depends(repo)]

    def require_token(authorization: Annotated[str | None, Header()] = None) -> None:
        if not settings.api_token:
            return
        expected = f"Bearer {settings.api_token}"
        if not authorization or not hmac.compare_digest(authorization, expected):
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "token inválido ou ausente")

    def inject_faults() -> None:
        if settings.fault_latency_ms:
            time.sleep(settings.fault_latency_ms / 1000)
        if settings.fault_error_rate and random.random() < settings.fault_error_rate:  # noqa: S311
            raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "falha injetada")

    @app.get("/healthz", include_in_schema=False)
    def healthz() -> dict[str, str]:
        # Liveness: só o processo. Não depende do banco para não reiniciar pods em cascata.
        return {"status": "ok"}

    @app.get("/readyz", include_in_schema=False)
    def readyz(r: Repo) -> JSONResponse:
        try:
            r.ping()
        except Exception as exc:  # noqa: BLE001
            log.warning("readiness falhou", extra={"error": str(exc)})
            return JSONResponse({"status": "unavailable"}, status.HTTP_503_SERVICE_UNAVAILABLE)
        return JSONResponse({"status": "ready"})

    @app.get("/metrics", include_in_schema=False)
    def metrics() -> PlainTextResponse:
        return PlainTextResponse(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    @app.get("/version")
    def version() -> dict[str, str]:
        return {"version": settings.version}

    @app.get("/api/items", response_model=list[ItemOut], dependencies=[Depends(inject_faults)])
    def list_items(r: Repo, limit: Annotated[int, Query(ge=1, le=100)] = 20) -> list[ItemOut]:
        return [ItemOut(**vars(i)) for i in r.list(limit)]

    @app.get("/api/items/{item_id}", response_model=ItemOut, dependencies=[Depends(inject_faults)])
    def get_item(item_id: int, r: Repo) -> ItemOut:
        item = r.get(item_id)
        if item is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "item não encontrado")
        return ItemOut(**vars(item))

    @app.post(
        "/api/items",
        response_model=ItemOut,
        status_code=status.HTTP_201_CREATED,
        dependencies=[Depends(require_token), Depends(inject_faults)],
    )
    def create_item(payload: ItemIn, r: Repo) -> ItemOut:
        item = r.create(payload.name, payload.description)
        log.info("item criado", extra={"item_id": item.id})
        return ItemOut(**vars(item))

    return app


def app() -> FastAPI:
    """Factory para o uvicorn (--factory)."""
    return create_app()
