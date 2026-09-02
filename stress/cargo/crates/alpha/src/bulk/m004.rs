pub fn value() -> i32 {
    4
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 4);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 8);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 12);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 16);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 20);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 24);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 28);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 32);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 36);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 40);
    }

}
