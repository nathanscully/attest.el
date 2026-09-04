import unittest

import pytest


def test_same():
    assert True


def test_uses_fixture(two):
    assert two == 2


def test_broken_fixture(broken):
    assert True


def test_broken_teardown(broken_teardown):
    assert True


def test_fails():
    x = 2
    assert x == 3


@pytest.mark.skip(reason="not now")
def test_skipped():
    assert False


@pytest.mark.xfail(reason="known bad")
def test_xfail():
    assert False


@pytest.mark.xfail(reason="unexpectedly passes")
def test_xpass():
    assert True


@pytest.mark.parametrize("n", [1, 2, 3])
def test_param(n):
    assert n > 0


@pytest.mark.parametrize("name", ["a (b) [c]?", "x.y/z:w", "unicodé"])
def test_param_metachars(name):
    assert name


@pytest.mark.parametrize("n", [1, 2])
def test_param_one_fails(n):
    assert n == 1


def test_raises():
    with pytest.raises(ValueError):
        int("x")


def test_prints_then_fails(capsys):
    print("captured stdout line one")
    assert 1 == 2


def helper_not_a_test():
    return 1


class TestOuter:
    def test_same(self):
        assert True

    def test_outer_fails(self):
        assert helper_not_a_test() == 2

    class TestInner:
        def test_same(self):
            assert True

        def test_inner_deep(self):
            assert 1 == 1


class TestLegacy(unittest.TestCase):
    def test_same(self):
        self.assertTrue(True)

    def test_legacy_fails(self):
        self.assertEqual(1, 2)

    @unittest.skip("legacy skip")
    def test_legacy_skipped(self):
        self.fail()


class NotCollected:
    def test_never_runs(self):
        assert False
