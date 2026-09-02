pub fn value() -> i32 {
    21
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 21);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 42);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 63);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 84);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 105);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 126);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 147);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 169);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 189);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 210);
    }

}
