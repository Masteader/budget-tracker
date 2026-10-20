"""
Session fixtures for the real-stack e2e suite.

Opt-in: nothing runs unless BT_E2E=1 (the stack rebuilds a local database and starts servers).
BT_E2E_SKIP_REBUILD=1 reuses an existing ``bt_e2e`` database instead of rebuilding it.
"""

from __future__ import annotations

import os
import shutil

import pytest

from e2e_harness import sandbox

E2E_ENABLED = os.environ.get("BT_E2E") == "1"


def pytest_collection_modifyitems(config, items):
    skip = pytest.mark.skip(reason="real-stack e2e suite: set BT_E2E=1 to run (see tests/e2e/README.md)")
    for item in items:
        item.add_marker(pytest.mark.e2e)
        if not E2E_ENABLED:
            item.add_marker(skip)


class Stack:
    def __init__(self):
        from e2e_harness import stack as st

        self.workdir = st.make_workdir()
        sandbox.install_network_guard()
        if os.environ.get("BT_E2E_SKIP_REBUILD") != "1":
            st.rebuild_database()
        st.prepare_authenticator()
        self.postgrest = st.PostgREST(self.workdir)
        self.postgrest.start()
        self.gateway = st.Gateway(self.postgrest.port)
        self.gateway.start()

        from e2e_harness import app_loader

        app_loader.configure_env(self.gateway.url)
        self.llm = sandbox.FakeLLM()
        self.llm.install()
        self.app = app_loader.load_app(self.workdir / "ai_data")
        import mail_service

        mail_service.RESEND_ENDPOINT = f"{self.gateway.url}/__resend/emails"
        self.server = st.AppServer()
        self.server.start(self.app)

    def stop(self):
        self.server.stop()
        self.gateway.stop()
        self.postgrest.stop()
        shutil.rmtree(self.workdir, ignore_errors=True)


@pytest.fixture(scope="session")
def stack():
    if not E2E_ENABLED:
        pytest.skip("BT_E2E=1 not set")
    s = Stack()
    yield s
    s.stop()
    assert not sandbox.blocked_connections(), f"outbound connections attempted: {sandbox.blocked_connections()}"


@pytest.fixture()
def llm(stack):
    stack.llm.clear()
    stack.llm.calls.clear()
    yield stack.llm
    stack.llm.clear()


@pytest.fixture()
def world(stack, llm):
    from e2e_harness.actors import World
    from rate_limiter import reset_rate_limiters

    reset_rate_limiters()
    w = World(stack.server.url, stack.gateway.url)
    yield w
    w.close()


@pytest.fixture()
def db(world):
    return world.db
