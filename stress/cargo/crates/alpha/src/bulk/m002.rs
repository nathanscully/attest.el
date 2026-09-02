pub fn value() -> i32 {
    2
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 2);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 4);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 6);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 8);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 10);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 12);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 14);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 16);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 18);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 20);
    }

}
