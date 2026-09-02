VALUE = 36


def test_check_01():
    assert VALUE * 1 == 36

def test_check_02():
    assert VALUE * 2 == 72

def test_check_03():
    assert VALUE * 3 == 108

def test_check_04():
    assert VALUE * 4 == 144

def test_check_05():
    assert VALUE * 5 == 180

def test_check_06():
    assert VALUE * 6 == 216

def test_check_07():
    assert VALUE * 7 == 252

def test_check_08():
    assert VALUE * 8 == 288

class TestBulk036:
    def test_extra_01(self):
        assert VALUE >= 1

    def test_extra_02(self):
        assert VALUE >= 2

    def test_extra_03(self):
        assert VALUE >= 3

    def test_extra_04(self):
        assert VALUE >= 4
