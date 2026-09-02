pub fn value() -> i32 {
    6
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 6);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 12);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 18);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 24);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 30);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 36);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 42);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 48);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 54);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 60);
    }

}
