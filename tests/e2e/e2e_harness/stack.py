"""
Bring up the e2e stack:

    pytest ──HTTP──▶ ai_service (uvicorn, real FastAPI app, in-process thread)
                          │ supabase-py (service_role JWT)
                          ▼
    pytest ──HTTP──▶ gateway (/rest/v1 → PostgREST, /storage/v1 stub, /__resend sink)
                          ▼
                     PostgREST 12 (real binary) ──▶ Postgres 16 (schema + all migrations)

Only the LLM (litellm) and the e-mail provider endpoint are faked; storage-api is stubbed
because it is not used by any scenario except image receipts (which are not exercised).
"""

from __future__ import annotations

import http.client
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Dict, List, Optional

import psycopg

from . import config


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_for_port(port: int, timeout: float = 30.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return
        except OSError:
            time.sleep(0.1)
    raise RuntimeError(f"port {port} did not open within {timeout}s")


# ─── Database ────────────────────────────────────────────────────────────────

def rebuild_database() -> None:
    """Drop/recreate the e2e DB from stubs + schema.sql + seed.sql + every migration."""
    env = dict(os.environ, PGHOST=config.PGHOST, PGPORT=str(config.PGPORT), PGUSER=config.PGUSER)
    proc = subprocess.run(
        [sys.executable, str(config.RUN_TESTS), "--psql", "--rebuild", "--db", config.DB_NAME, "--no-tests"],
        env=env, capture_output=True, text=True, timeout=900,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"DB rebuild failed:\n{proc.stdout}\n{proc.stderr}")


def prepare_authenticator() -> None:
    """Create the PostgREST login role (cluster-wide, idempotent) with Supabase's role grants."""
    with psycopg.connect(config.pg_dsn(), autocommit=True) as conn:
        conn.execute(
            f"""
            DO $$
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '{config.AUTHENTICATOR_ROLE}') THEN
                    CREATE ROLE {config.AUTHENTICATOR_ROLE} LOGIN NOINHERIT;
                END IF;
            END $$;
            """
        )
        conn.execute(f"GRANT anon, authenticated, service_role TO {config.AUTHENTICATOR_ROLE}")
        conn.execute(f"GRANT CONNECT ON DATABASE {config.DB_NAME} TO {config.AUTHENTICATOR_ROLE}")


# ─── PostgREST ───────────────────────────────────────────────────────────────

def locate_postgrest() -> str:
    explicit = os.environ.get("BT_E2E_POSTGREST_BIN")
    if explicit:
        return explicit
    found = shutil.which("postgrest")
    if found:
        return found
    proc = subprocess.run([str(config.FETCH_POSTGREST)], capture_output=True, text=True, timeout=600)
    if proc.returncode != 0:
        raise RuntimeError(f"PostgREST binary not found and download failed:\n{proc.stderr}")
    return proc.stdout.strip().splitlines()[-1]


class PostgREST:
    def __init__(self, workdir: Path):
        self.port = free_port()
        self.binary = locate_postgrest()
        self.conf = workdir / "postgrest.conf"
        self.log = workdir / "postgrest.log"
        self.proc: Optional[subprocess.Popen] = None

    def start(self) -> None:
        self.conf.write_text(
            "\n".join([
                f'db-uri = "postgres://{config.AUTHENTICATOR_ROLE}@{config.PGHOST}:{config.PGPORT}/{config.DB_NAME}"',
                'db-schemas = "public"',
                'db-anon-role = "anon"',
                'db-extra-search-path = "public, extensions"',
                f'jwt-secret = "{config.JWT_SECRET}"',
                'jwt-secret-is-base64 = false',
                'server-host = "127.0.0.1"',
                f"server-port = {self.port}",
                "db-pool = 10",
                "db-channel-enabled = false",
                'log-level = "warn"',
            ]) + "\n"
        )
        self._log_fh = open(self.log, "wb")
        self.proc = subprocess.Popen([self.binary, str(self.conf)], stdout=self._log_fh, stderr=subprocess.STDOUT)
        deadline = time.time() + 30
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError(f"PostgREST exited: {self.log.read_text()}")
            try:
                conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=1)
                conn.request("GET", "/")
                if conn.getresponse().status in (200, 401):
                    return
            except OSError:
                pass
            time.sleep(0.2)
        raise RuntimeError(f"PostgREST did not become ready: {self.log.read_text()}")

    def stop(self) -> None:
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        if getattr(self, "_log_fh", None):
            self._log_fh.close()


# ─── Gateway (Supabase-style URL layout in front of PostgREST) ───────────────

_HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailers",
        "transfer-encoding", "upgrade", "host", "content-length"}


class Gateway:
    """
    Kong stand-in: ``/rest/v1/*`` is proxied byte-for-byte to PostgREST; ``/storage/v1/*`` is a
    minimal in-memory object store; ``/__resend/emails`` captures e-mails the app would send via
    Resend; ``/auth/v1/.well-known/jwks.json`` serves an empty key set (HS256 only).
    """

    def __init__(self, postgrest_port: int):
        self.port = free_port()
        self.postgrest_port = postgrest_port
        self.storage: Dict[str, bytes] = {}
        self.emails: List[dict] = []
        self.resend_status = 200
        self.rest_log: List[tuple] = []
        gateway = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *args):  # quiet
                pass

            def _body(self) -> bytes:
                length = int(self.headers.get("Content-Length") or 0)
                return self.rfile.read(length) if length else b""

            def _send(self, status: int, payload, headers: Optional[dict] = None) -> None:
                data = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
                self.send_response(status)
                self.send_header("Content-Type", (headers or {}).pop("Content-Type", "application/json"))
                for k, v in (headers or {}).items():
                    self.send_header(k, v)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def _proxy(self) -> None:
                body = self._body()
                path = self.path[len("/rest/v1"):] or "/"
                conn = http.client.HTTPConnection("127.0.0.1", gateway.postgrest_port, timeout=60)
                headers = {k: v for k, v in self.headers.items() if k.lower() not in _HOP}
                if body:
                    headers["Content-Length"] = str(len(body))
                conn.request(self.command, path, body=body or None, headers=headers)
                resp = conn.getresponse()
                data = resp.read()
                gateway.rest_log.append((self.command, path, resp.status))
                self.send_response(resp.status)
                for k, v in resp.getheaders():
                    if k.lower() not in _HOP:
                        self.send_header(k, v)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(data)
                conn.close()

            def _storage(self) -> None:
                body = self._body()
                parsed = urllib.parse.urlparse(self.path)
                key = parsed.path[len("/storage/v1/object/"):]
                if self.command in ("POST", "PUT") and parsed.path.startswith("/storage/v1/object/"):
                    gateway.storage[key] = body
                    self._send(200, {"Key": key, "Id": key})
                elif self.command == "GET" and key in gateway.storage:
                    self._send(200, gateway.storage[key], {"Content-Type": "application/octet-stream"})
                else:
                    self._send(404, {"statusCode": "404", "error": "not_found", "message": "Object not found"})

            def _dispatch(self) -> None:
                if self.path.startswith("/rest/v1"):
                    return self._proxy()
                if self.path.startswith("/storage/v1/"):
                    return self._storage()
                if self.path.startswith("/__resend/emails") and self.command == "POST":
                    payload = json.loads(self._body() or b"{}")
                    payload["_authorization"] = self.headers.get("Authorization")
                    gateway.emails.append(payload)
                    return self._send(gateway.resend_status, {"id": f"e2e-{len(gateway.emails)}"})
                if self.path.startswith("/auth/v1/.well-known/jwks.json"):
                    return self._send(200, {"keys": []})
                self._body()
                self._send(404, {"message": "not routed by e2e gateway"})

            do_GET = do_POST = do_PATCH = do_PUT = do_DELETE = do_HEAD = do_OPTIONS = _dispatch

        self.server = ThreadingHTTPServer(("127.0.0.1", self.port), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, name="e2e-gateway", daemon=True)

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    def start(self) -> None:
        self.thread.start()
        wait_for_port(self.port)

    def stop(self) -> None:
        self.server.shutdown()
        self.server.server_close()


# ─── ai_service ──────────────────────────────────────────────────────────────

class AppServer:
    """The real FastAPI app served by uvicorn on a loopback port inside the test process."""

    def __init__(self):
        self.port = free_port()
        self.server = None
        self.thread: Optional[threading.Thread] = None

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    def start(self, app) -> None:
        import uvicorn

        cfg = uvicorn.Config(app, host="127.0.0.1", port=self.port, log_level="warning", lifespan="off",
                             access_log=False)
        self.server = uvicorn.Server(cfg)
        self.thread = threading.Thread(target=self.server.run, name="e2e-ai-service", daemon=True)
        self.thread.start()
        wait_for_port(self.port)

    def stop(self) -> None:
        if self.server:
            self.server.should_exit = True
        if self.thread:
            self.thread.join(timeout=10)


def make_workdir() -> Path:
    return Path(tempfile.mkdtemp(prefix="bt-e2e-"))
