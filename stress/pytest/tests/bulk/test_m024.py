VALUE = 24


def test_check_01():
    assert VALUE * 1 == 24

def test_check_02():
    assert VALUE * 2 == 48

def test_check_03():
    assert VALUE * 3 == 72

def test_check_04():
    assert VALUE * 4 == 96

def test_check_05():
    assert VALUE * 5 == 120

def test_check_06():
    assert VALUE * 6 == 144

def test_check_07():
    assert VALUE * 7 == 168

def test_check_08():
    assert VALUE * 8 == 192

class TestBulk024:
    def test_extra_01(self):
        assert VALUE >= 1

    def test_extra_02(self):
        assert VALUE >= 2

    def test_extra_03(self):
        assert VALUE >= 3

    def test_extra_04(self):
        assert VALUE >= 4
