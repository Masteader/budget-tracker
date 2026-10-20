"""
Process-level safety net and fakes for the e2e run.

* ``install_network_guard``: every outbound TCP connect from this process must target a loopback
  address. A stray call to a hosted Supabase project, an LLM API or an e-mail provider fails
  loudly instead of leaving the machine. (libpq connections are made in C and go to localhost.)
* ``FakeLLM``: replaces ``litellm.completion`` / ``litellm.acompletion``. Tests queue the JSON the
  model would return; with an empty queue the call raises, which makes the app use its
  documented heuristic fallback.
"""

from __future__ import annotations

import ipaddress
import json
import os
import socket
import threading
from types import SimpleNamespace
from typing import Any, List

_original_connect = socket.socket.connect
_original_connect_ex = socket.socket.connect_ex
_blocked: List[str] = []


def _is_loopback(address: Any) -> bool:
    if isinstance(address, (str, bytes)):  # AF_UNIX path
        return True
    host = address[0] if isinstance(address, tuple) and address else ""
    if host in ("localhost",):
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def _guarded_connect(self, address):
    if self.family in (socket.AF_INET, socket.AF_INET6) and not _is_loopback(address):
        _blocked.append(repr(address))
        raise ConnectionRefusedError(f"e2e network guard: outbound connection to {address!r} blocked")
    return _original_connect(self, address)


def _guarded_connect_ex(self, address):
    if self.family in (socket.AF_INET, socket.AF_INET6) and not _is_loopback(address):
        _blocked.append(repr(address))
        return 111  # ECONNREFUSED
    return _original_connect_ex(self, address)


def install_network_guard() -> None:
    for var in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"):
        os.environ.pop(var, None)
    os.environ["NO_PROXY"] = os.environ["no_proxy"] = "127.0.0.1,localhost,::1"
    # litellm downloads its model price map from GitHub at import time unless told not to.
    os.environ["LITELLM_LOCAL_MODEL_COST_MAP"] = "True"
    socket.socket.connect = _guarded_connect
    socket.socket.connect_ex = _guarded_connect_ex


def blocked_connections() -> List[str]:
    return list(_blocked)


class FakeLLM:
    def __init__(self) -> None:
        self._queue: List[Any] = []
        self.calls: List[dict] = []
        self._lock = threading.Lock()

    def queue_json(self, payload: dict) -> None:
        with self._lock:
            self._queue.append(payload)

    def clear(self) -> None:
        with self._lock:
            self._queue.clear()

    def _next(self, kwargs: dict):
        with self._lock:
            self.calls.append({"model": kwargs.get("model"), "messages": kwargs.get("messages")})
            if not self._queue:
                raise RuntimeError("e2e FakeLLM: no response queued (LLM disabled)")
            payload = self._queue.pop(0)
        content = payload if isinstance(payload, str) else json.dumps(payload)
        return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=content))])

    def completion(self, *args, **kwargs):
        return self._next(kwargs)

    async def acompletion(self, *args, **kwargs):
        return self._next(kwargs)

    def install(self) -> None:
        import litellm

        litellm.completion = self.completion
        litellm.acompletion = self.acompletion
