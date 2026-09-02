pub fn value() -> i32 {
    7
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 7);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 14);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 21);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 28);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 35);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 42);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 49);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 57);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 63);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 70);
    }

}
