import pytest


@pytest.mark.parametrize("value", [False, True], ids=["bad::case", "good"])
def test_case(value):
    assert value
