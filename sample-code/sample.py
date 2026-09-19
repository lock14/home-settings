"""Module demonstrating Solarized Dark syntax highlighting for Python.

Showcases decorators, type hints, dataclasses, async routines,
and exception handling.
"""

from __future__ import annotations

import asyncio
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

# Constant definitions
DEFAULT_PORT: int = 8080
MAX_RETRIES: int = 5
CACHE_HEX_MASK: int = 0xFF00_AA55
PI_APPROX: float = 3.1415926535


def timed_execution(func: Callable[..., Any]) -> Callable[..., Any]:
    """Decorator measuring asynchronous execution duration."""
    async def wrapper(*args: Any, **kwargs: Any) -> Any:
        start_time = datetime.now(timezone.utc)
        try:
            return await func(*args, **kwargs)
        finally:
            elapsed = (datetime.now(timezone.utc) - start_time).total_seconds()
            print(f"[METRICS] {func.__name__} finished in {elapsed:.4f}s")
    return wrapper


@dataclass(frozen=True)
class EndpointMetrics:
    path: str
    status_code: int
    duration_ms: float
    metadata: dict[str, str | int | bool] = field(default_factory=dict)
    tags: set[str] = field(default_factory=set)
    headers: list[tuple[str, str]] = field(default_factory=list)
    active: bool = True

    @property
    def is_success(self) -> bool:
        """Returns True if the response code indicates HTTP 2xx success."""
        return 200 <= self.status_code < 300

    def summary(self) -> str:
        return f"Endpoint: {self.path} -> {self.status_code} ({self.duration_ms:.1f}ms)"


class MetricsCollector:
    """Collects and aggregates endpoint performance statistics."""

    def __init__(self, service_name: str) -> None:
        self.service_name = service_name
        self._buffer: list[EndpointMetrics] = []

    def record(self, metric: EndpointMetrics | None) -> None:
        if metric is None:
            raise ValueError("metric argument cannot be None")
        self._buffer.append(metric)

    @timed_execution
    async def flush(self) -> int:
        await asyncio.sleep(0.02)
        count = len(self._buffer)
        self._buffer.clear()
        return count


async def main() -> None:
    collector = MetricsCollector("Solarized-Telemetry")
    collector.record(EndpointMetrics("/health", 200, 1.45, {"cached": True}))
    collector.record(EndpointMetrics("/api/v1/users", 201, 14.2, {"cached": False}))

    total_flushed = await collector.flush()
    print(f"Flushed {total_flushed} events (mask: 0x{CACHE_HEX_MASK:X})")


if __name__ == "__main__":
    asyncio.run(main())
