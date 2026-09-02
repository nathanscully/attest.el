pub fn value() -> i32 {
    30
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 30);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 60);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 90);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 120);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 150);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 180);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 210);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 240);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 270);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 300);
    }

}
