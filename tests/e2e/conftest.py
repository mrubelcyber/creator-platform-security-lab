import os

import pytest

@pytest.fixture(scope="session")
def base_url():
    return "http://127.0.0.1:5000"


@pytest.fixture(scope="session")
def admin_password():
    password = os.environ.get("E2E_ADMIN_PASSWORD")
    if not password:
        pytest.skip("Set E2E_ADMIN_PASSWORD to run the browser tests")
    return password
