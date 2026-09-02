pub fn value() -> i32 {
    27
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 27);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 54);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 81);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 108);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 135);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 162);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 189);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 216);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 243);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 270);
    }

}
