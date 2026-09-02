pub fn value() -> i32 {
    18
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 18);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 36);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 54);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 72);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 90);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 108);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 126);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 144);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 162);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 180);
    }

}
