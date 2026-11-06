"""Teste de integração. Roda no CI com um Postgres de serviço; localmente: make test-integration."""

import os

import pytest

from platform_api.repository import PostgresRepository

DSN = os.getenv("TEST_DATABASE_URL")

pytestmark = pytest.mark.skipif(not DSN, reason="TEST_DATABASE_URL não definido")


def test_postgres_roundtrip():
    repo = PostgresRepository(DSN, 1, 2, 5.0)
    try:
        repo.ping()
        created = repo.create("integração", None)
        assert repo.get(created.id) == created
        assert created in repo.list(10)
    finally:
        repo.close()
