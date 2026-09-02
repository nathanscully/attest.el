VALUE = 14


def test_check_01():
    assert VALUE * 1 == 14

def test_check_02():
    assert VALUE * 2 == 28

def test_check_03():
    assert VALUE * 3 == 42

def test_check_04():
    assert VALUE * 4 == 56

def test_check_05():
    assert VALUE * 5 == 71

def test_check_06():
    assert VALUE * 6 == 84

def test_check_07():
    assert VALUE * 7 == 98

def test_check_08():
    assert VALUE * 8 == 112

class TestBulk014:
    def test_extra_01(self):
        assert VALUE >= 1

    def test_extra_02(self):
        assert VALUE >= 2

    def test_extra_03(self):
        assert VALUE >= 3

    def test_extra_04(self):
        assert VALUE >= 4
