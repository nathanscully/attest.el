import pytest


def make_test(n):
    def test(self):
        assert n > 0

    test.__name__ = f"test_generated_{n}"
    return test


class TestGenerated:
    pass


for i in range(1, 4):
    setattr(TestGenerated, f"test_generated_{i}", make_test(i))


@pytest.mark.parametrize("n", range(3), ids=lambda n: f"id-{n}")
def test_custom_ids(n):
    assert n >= 0
