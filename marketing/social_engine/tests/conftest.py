"""Hermetic environment for the whole suite (plan Section 1, task A1).

Blocks DNS and any connection except loopback, from collection onwards. This is not
`pytest-socket --disable-socket`, because Windows asyncio needs a local socket pair for
its event loop. Real secrets are removed from the environment, and %LOCALAPPDATA% points
at a temporary folder, so no test can reach the real `.env` or the real `data_root`.
"""

import ipaddress
import os
import socket
import sys

import pytest


class NetworkBlocked(RuntimeError):
    """A test tried to reach something other than loopback. Not an OSError on purpose:
    code that handles connection errors must not swallow it and carry on."""


SECRET_ENV_NAMES = (
    "TELEGRAM_BOT_TOKEN",
    "TELEGRAM_OWNER_USER_ID",
    "AZURE_SPEECH_KEY",
    "AZURE_SPEECH_REGION",
    "ANTHROPIC_API_KEY",
    "ANTHROPIC_AUTH_TOKEN",
    "CLAUDE_CODE_OAUTH_TOKEN",
    "PUBLISHER_API_KEY",
)
_SECRET_ENV_PREFIXES = ("SUPA" + "BASE_",)

_LOCAL_NAMES = {"localhost", "ip6-localhost", "ip6-loopback"}


def _as_text(host) -> str | None:
    if isinstance(host, bytes | bytearray):
        return bytes(host).decode("ascii", "replace")
    return host


def _is_loopback(host, *, allow_wildcard: bool = False) -> bool:
    host = _as_text(host)
    if not isinstance(host, str):
        return False
    if host == "":
        return allow_wildcard
    if host.lower() in _LOCAL_NAMES:
        return True
    try:
        address = ipaddress.ip_address(host.partition("%")[0])
    except ValueError:
        return False
    address = getattr(address, "ipv4_mapped", None) or address
    return address.is_loopback or (allow_wildcard and address.is_unspecified)


def _check_address(address) -> None:
    # A plain string is an AF_UNIX path, which is local by definition.
    if isinstance(address, str | bytes | bytearray):
        return
    if not _is_loopback(address[0]):
        raise NetworkBlocked(f"connection to {address[0]!r} blocked in tests")


def _check_lookup(host) -> None:
    if host is not None and not _is_loopback(host, allow_wildcard=True):
        raise NetworkBlocked(f"DNS lookup of {_as_text(host)!r} blocked in tests")


_originals: list[tuple[object, str, object]] = []


def _replace(owner, name, replacement) -> None:
    _originals.append((owner, name, getattr(owner, name)))
    setattr(owner, name, replacement)


def _install_network_ban() -> None:
    real_getaddrinfo = socket.getaddrinfo
    real_gethostbyname = socket.gethostbyname
    real_gethostbyname_ex = socket.gethostbyname_ex
    real_gethostbyaddr = socket.gethostbyaddr
    real_connect = socket.socket.connect
    real_connect_ex = socket.socket.connect_ex
    real_sendto = socket.socket.sendto

    def getaddrinfo(host, *args, **kwargs):
        _check_lookup(host)
        return real_getaddrinfo(host, *args, **kwargs)

    def gethostbyname(host):
        _check_lookup(host)
        return real_gethostbyname(host)

    def gethostbyname_ex(host):
        _check_lookup(host)
        return real_gethostbyname_ex(host)

    def gethostbyaddr(host):
        _check_lookup(host)
        return real_gethostbyaddr(host)

    def connect(self, address):
        _check_address(address)
        return real_connect(self, address)

    def connect_ex(self, address):
        _check_address(address)
        return real_connect_ex(self, address)

    def sendto(self, data, *rest):
        _check_address(rest[-1])
        return real_sendto(self, data, *rest)

    _replace(socket, "getaddrinfo", getaddrinfo)
    _replace(socket, "gethostbyname", gethostbyname)
    _replace(socket, "gethostbyname_ex", gethostbyname_ex)
    _replace(socket, "gethostbyaddr", gethostbyaddr)
    _replace(socket.socket, "connect", connect)
    _replace(socket.socket, "connect_ex", connect_ex)
    _replace(socket.socket, "sendto", sendto)

    if sys.platform == "win32":
        # The proactor loop connects through ConnectEx, not socket.connect, and a numeric
        # address skips getaddrinfo, so asyncio clients need this guard as well.
        from asyncio.windows_events import IocpProactor

        real_proactor_connect = IocpProactor.connect

        def proactor_connect(self, conn, address):
            _check_address(address)
            return real_proactor_connect(self, conn, address)

        _replace(IocpProactor, "connect", proactor_connect)


def _uninstall_network_ban() -> None:
    while _originals:
        owner, name, original = _originals.pop()
        setattr(owner, name, original)


def _secret_names_in(environ) -> list[str]:
    return [
        name
        for name in environ
        if name.upper() in SECRET_ENV_NAMES or name.upper().startswith(_SECRET_ENV_PREFIXES)
    ]


def pytest_configure(config):
    # Here, rather than in a fixture, so that collection and imports are covered as well.
    _install_network_ban()
    for name in _secret_names_in(os.environ):
        del os.environ[name]


def pytest_unconfigure(config):
    _uninstall_network_ban()


@pytest.fixture(autouse=True)
def _hermetic_environment(monkeypatch, tmp_path):
    for name in _secret_names_in(os.environ):
        monkeypatch.delenv(name)
    monkeypatch.setenv("LOCALAPPDATA", str(tmp_path / "localappdata"))
