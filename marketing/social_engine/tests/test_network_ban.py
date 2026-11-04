"""The suite-wide network ban and environment scrub (spec Section 12, task A1)."""

import asyncio
import os
import socket

import pytest
from conftest import SECRET_ENV_NAMES, NetworkBlocked


def test_create_connection_to_a_public_host_is_blocked():
    with pytest.raises(NetworkBlocked):
        socket.create_connection(("example.com", 80))


def test_dns_lookup_of_a_public_host_is_blocked():
    with pytest.raises(NetworkBlocked):
        socket.getaddrinfo("example.com", 80)


@pytest.mark.parametrize("lookup", ["gethostbyname", "gethostbyname_ex"])
def test_legacy_dns_lookups_are_blocked(lookup):
    with pytest.raises(NetworkBlocked):
        getattr(socket, lookup)("example.com")


def test_look_alike_of_localhost_is_blocked():
    with pytest.raises(NetworkBlocked):
        socket.getaddrinfo("localhost.example.com", 80)


@pytest.mark.parametrize(
    "address",
    [("203.0.113.10", 80), ("2001:db8::1", 80)],
)
def test_direct_connect_to_a_public_ip_is_blocked(address):
    family = socket.AF_INET6 if ":" in address[0] else socket.AF_INET
    with socket.socket(family, socket.SOCK_STREAM) as sock:
        with pytest.raises(NetworkBlocked):
            sock.connect(address)
        with pytest.raises(NetworkBlocked):
            sock.connect_ex(address)


def test_udp_send_to_a_public_ip_is_blocked():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        with pytest.raises(NetworkBlocked):
            sock.sendto(b"x", ("192.0.2.1", 53))
        with pytest.raises(NetworkBlocked):
            sock.sendto(b"x", 0, ("192.0.2.1", 53))


def test_asyncio_connect_to_a_public_ip_is_blocked():
    # The Windows proactor loop calls ConnectEx directly and never reaches socket.connect,
    # and a numeric IP skips getaddrinfo, so this path needs its own guard.
    async def main():
        await asyncio.open_connection("203.0.113.10", 80)

    with pytest.raises(NetworkBlocked):
        asyncio.run(main())


def test_loopback_socket_pair_still_works():
    left, right = socket.socketpair()
    with left, right:
        left.sendall(b"ping")
        assert right.recv(4) == b"ping"


def test_loopback_tcp_connection_still_works():
    with socket.socket() as server:
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        with socket.create_connection(server.getsockname()) as client:
            accepted, _ = server.accept()
            with accepted:
                client.sendall(b"ok")
                assert accepted.recv(2) == b"ok"


def test_asyncio_run_of_a_trivial_coroutine_still_works():
    async def trivial():
        await asyncio.sleep(0)
        return 42

    assert asyncio.run(trivial()) == 42


def test_asyncio_loopback_connection_still_works():
    async def main():
        async def handle(reader, writer):
            writer.write(await reader.readexactly(2))
            await writer.drain()
            writer.close()

        server = await asyncio.start_server(handle, "127.0.0.1", 0)
        port = server.sockets[0].getsockname()[1]
        async with server:
            reader, writer = await asyncio.open_connection("127.0.0.1", port)
            writer.write(b"hi")
            await writer.drain()
            data = await reader.readexactly(2)
            writer.close()
            await writer.wait_closed()
            return data

    assert asyncio.run(main()) == b"hi"


def test_secret_variables_are_removed_from_the_test_environment():
    assert SECRET_ENV_NAMES, "the scrub list must not be empty"
    for name in SECRET_ENV_NAMES:
        assert name not in os.environ, f"{name} leaked into the test environment"
    assert not [name for name in os.environ if name.upper().startswith("SUPA" + "BASE_")]


def test_local_app_data_points_at_a_temporary_folder(tmp_path):
    # So nothing that expands %LOCALAPPDATA% in a test can reach the real data_root.
    assert os.environ["LOCALAPPDATA"].startswith(str(tmp_path))
