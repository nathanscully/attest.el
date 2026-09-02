pub fn value() -> i32 {
    9
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 9);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 18);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 27);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 36);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 45);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 54);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 63);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 72);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 81);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 90);
    }

}
