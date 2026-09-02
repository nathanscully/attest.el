VALUE = 11


def test_check_01():
    assert VALUE * 1 == 11

def test_check_02():
    assert VALUE * 2 == 22

def test_check_03():
    assert VALUE * 3 == 33

def test_check_04():
    assert VALUE * 4 == 44

def test_check_05():
    assert VALUE * 5 == 55

def test_check_06():
    assert VALUE * 6 == 66

def test_check_07():
    assert VALUE * 7 == 77

def test_check_08():
    assert VALUE * 8 == 88

class TestBulk011:
    def test_extra_01(self):
        assert VALUE >= 1

    def test_extra_02(self):
        assert VALUE >= 2

    def test_extra_03(self):
        assert VALUE >= 3

    def test_extra_04(self):
        assert VALUE >= 4
