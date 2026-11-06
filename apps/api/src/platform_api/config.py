from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Configuração lida de variáveis de ambiente com prefixo APP_."""

    model_config = SettingsConfigDict(env_prefix="APP_", extra="ignore")

    database_url: str | None = None
    api_token: str | None = Field(default=None, repr=False)
    log_level: str = "INFO"
    version: str = "dev"

    db_pool_min: int = 1
    db_pool_max: int = 5
    db_timeout_seconds: float = 2.0

    # Injeção de falhas para exercícios de SLO/alertas. Afeta apenas /api/*.
    fault_error_rate: float = Field(default=0.0, ge=0.0, le=1.0)
    fault_latency_ms: int = Field(default=0, ge=0, le=10_000)


@lru_cache
def get_settings() -> Settings:
    return Settings()
