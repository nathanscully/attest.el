VALUE = 40


def test_check_01():
    assert VALUE * 1 == 40

def test_check_02():
    assert VALUE * 2 == 80

def test_check_03():
    assert VALUE * 3 == 120

def test_check_04():
    assert VALUE * 4 == 160

def test_check_05():
    assert VALUE * 5 == 200

def test_check_06():
    assert VALUE * 6 == 240

def test_check_07():
    assert VALUE * 7 == 280

def test_check_08():
    assert VALUE * 8 == 320

class TestBulk040:
    def test_extra_01(self):
        assert VALUE >= 1

    def test_extra_02(self):
        assert VALUE >= 2

    def test_extra_03(self):
        assert VALUE >= 3

    def test_extra_04(self):
        assert VALUE >= 4
