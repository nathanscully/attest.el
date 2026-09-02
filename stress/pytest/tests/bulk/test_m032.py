VALUE = 32


def test_check_01():
    assert VALUE * 1 == 32

def test_check_02():
    assert VALUE * 2 == 64

def test_check_03():
    assert VALUE * 3 == 96

def test_check_04():
    assert VALUE * 4 == 128

def test_check_05():
    assert VALUE * 5 == 160

def test_check_06():
    assert VALUE * 6 == 192

def test_check_07():
    assert VALUE * 7 == 224

def test_check_08():
    assert VALUE * 8 == 256

class TestBulk032:
    def test_extra_01(self):
        assert VALUE >= 1

    def test_extra_02(self):
        assert VALUE >= 2

    def test_extra_03(self):
        assert VALUE >= 3

    def test_extra_04(self):
        assert VALUE >= 4
