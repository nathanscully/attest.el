pub fn value() -> i32 {
    15
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 15);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 30);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 45);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 60);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 75);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 90);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 105);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 120);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 135);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 150);
    }

}
