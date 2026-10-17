import hashlib
from collections.abc import Iterator
from contextlib import contextmanager

from sqlalchemy import text
from sqlalchemy.engine import Engine


def lock_key(name: str) -> int:
    """Stable signed 64-bit key for pg_advisory_lock."""
    return int.from_bytes(hashlib.blake2b(f"weather:{name}".encode(), digest_size=8).digest(), "big", signed=True)


@contextmanager
def advisory_lock(engine: Engine, name: str) -> Iterator[bool]:
    """Session-level Postgres advisory lock held on a dedicated connection.
    Yields False (without blocking) if another process already holds it, so the
    same job never runs twice concurrently across scheduler/API replicas."""
    key = lock_key(name)
    with engine.connect() as conn:
        acquired = bool(conn.execute(text("SELECT pg_try_advisory_lock(:k)"), {"k": key}).scalar())
        conn.commit()
        try:
            yield acquired
        finally:
            if acquired:
                conn.execute(text("SELECT pg_advisory_unlock(:k)"), {"k": key})
                conn.commit()
