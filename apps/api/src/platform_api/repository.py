from __future__ import annotations

import threading
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Protocol

from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

SCHEMA = """
CREATE TABLE IF NOT EXISTS items (
    id          BIGSERIAL PRIMARY KEY,
    name        TEXT        NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""


@dataclass(frozen=True)
class Item:
    id: int
    name: str
    description: str | None
    created_at: datetime


class ItemRepository(Protocol):
    def ping(self) -> None: ...
    def list(self, limit: int) -> list[Item]: ...
    def get(self, item_id: int) -> Item | None: ...
    def create(self, name: str, description: str | None) -> Item: ...
    def close(self) -> None: ...


class PostgresRepository:
    def __init__(self, dsn: str, min_size: int, max_size: int, timeout: float) -> None:
        # open=False: o processo sobe mesmo sem banco; a readiness reflete o estado real.
        self._pool = ConnectionPool(
            dsn,
            min_size=min_size,
            max_size=max_size,
            timeout=timeout,
            open=False,
            kwargs={"connect_timeout": max(1, int(timeout)), "row_factory": dict_row},
        )
        self._timeout = timeout
        self._schema_ready = False
        self._lock = threading.Lock()

    def _ensure_open(self) -> None:
        if self._pool.closed:
            with self._lock:
                if self._pool.closed:
                    self._pool.open(wait=False)

    def _ensure_schema(self) -> None:
        if self._schema_ready:
            return
        with self._lock:
            if self._schema_ready:
                return
            with self._pool.connection(timeout=self._timeout) as conn:
                conn.execute(SCHEMA)
            self._schema_ready = True

    def ping(self) -> None:
        self._ensure_open()
        with self._pool.connection(timeout=self._timeout) as conn:
            conn.execute("SELECT 1")
        self._ensure_schema()

    def list(self, limit: int) -> list[Item]:
        self._ensure_open()
        self._ensure_schema()
        with self._pool.connection(timeout=self._timeout) as conn:
            rows = conn.execute(
                "SELECT id, name, description, created_at FROM items ORDER BY id DESC LIMIT %s",
                (limit,),
            ).fetchall()
        return [Item(**row) for row in rows]

    def get(self, item_id: int) -> Item | None:
        self._ensure_open()
        self._ensure_schema()
        with self._pool.connection(timeout=self._timeout) as conn:
            row = conn.execute(
                "SELECT id, name, description, created_at FROM items WHERE id = %s",
                (item_id,),
            ).fetchone()
        return Item(**row) if row else None

    def create(self, name: str, description: str | None) -> Item:
        self._ensure_open()
        self._ensure_schema()
        with self._pool.connection(timeout=self._timeout) as conn:
            row = conn.execute(
                "INSERT INTO items (name, description) VALUES (%s, %s) "
                "RETURNING id, name, description, created_at",
                (name, description),
            ).fetchone()
        return Item(**row)

    def close(self) -> None:
        self._pool.close()


class InMemoryRepository:
    """Usado nos testes unitários e quando APP_DATABASE_URL não está definido."""

    def __init__(self) -> None:
        self._items: dict[int, Item] = {}
        self._next_id = 1
        self._lock = threading.Lock()
        self.healthy = True

    def ping(self) -> None:
        if not self.healthy:
            raise ConnectionError("in-memory repository marked unhealthy")

    def list(self, limit: int) -> list[Item]:
        return sorted(self._items.values(), key=lambda i: i.id, reverse=True)[:limit]

    def get(self, item_id: int) -> Item | None:
        return self._items.get(item_id)

    def create(self, name: str, description: str | None) -> Item:
        with self._lock:
            item = Item(self._next_id, name, description, datetime.now(UTC))
            self._items[item.id] = item
            self._next_id += 1
        return item

    def close(self) -> None:
        self._items.clear()
