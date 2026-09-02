pub fn value() -> i32 {
    8
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 8);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 16);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 24);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 32);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 40);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 48);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 56);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 64);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 72);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 80);
    }

}
