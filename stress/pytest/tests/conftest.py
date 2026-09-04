import pytest


@pytest.fixture
def two():
    return 2


@pytest.fixture
def broken():
    raise RuntimeError("fixture exploded")


@pytest.fixture
def broken_teardown():
    yield
    raise RuntimeError("teardown exploded")
