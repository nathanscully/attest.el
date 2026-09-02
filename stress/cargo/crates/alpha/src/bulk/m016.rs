pub fn value() -> i32 {
    16
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 16);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 32);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 48);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 64);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 80);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 96);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 112);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 128);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 144);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 160);
    }

}
