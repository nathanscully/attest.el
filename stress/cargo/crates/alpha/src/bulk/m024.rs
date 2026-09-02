pub fn value() -> i32 {
    24
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 24);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 48);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 72);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 96);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 120);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 144);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 168);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 192);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 216);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 240);
    }

}
