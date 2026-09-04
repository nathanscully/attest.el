import pytest


def add(a, b):
    return a + b


def test_adds():
    assert add(1, 1) == 2


def test_fails_on_purpose():
    x = 2
    assert x == 3, "x should be three"


@pytest.mark.skip(reason="not yet")
def test_skipped():
    pass


@pytest.mark.parametrize("n", [1, 2])
def test_param(n):
    assert n > 0


class TestScanner:
    def test_counts(self):
        assert len("a b".split()) == 2

    def test_raises(self):
        raise RuntimeError("boom")


@pytest.fixture
def bad_teardown():
    yield
    raise RuntimeError("teardown boom")


def test_teardown_fails(bad_teardown):
    assert True
