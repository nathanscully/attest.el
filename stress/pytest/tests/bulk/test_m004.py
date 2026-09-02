VALUE = 4


def test_check_01():
    assert VALUE * 1 == 4

def test_check_02():
    assert VALUE * 2 == 8

def test_check_03():
    assert VALUE * 3 == 12

def test_check_04():
    assert VALUE * 4 == 16

def test_check_05():
    assert VALUE * 5 == 20

def test_check_06():
    assert VALUE * 6 == 24

def test_check_07():
    assert VALUE * 7 == 28

def test_check_08():
    assert VALUE * 8 == 32

class TestBulk004:
    def test_extra_01(self):
        assert VALUE >= 1

    def test_extra_02(self):
        assert VALUE >= 2

    def test_extra_03(self):
        assert VALUE >= 3

    def test_extra_04(self):
        assert VALUE >= 4
