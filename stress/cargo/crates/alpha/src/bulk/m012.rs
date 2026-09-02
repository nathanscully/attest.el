pub fn value() -> i32 {
    12
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 12);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 24);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 36);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 48);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 60);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 72);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 84);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 96);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 108);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 120);
    }

}
