pub fn value() -> i32 {
    3
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 3);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 6);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 9);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 12);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 15);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 18);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 21);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 24);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 27);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 30);
    }

}
