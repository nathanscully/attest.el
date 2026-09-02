pub fn value() -> i32 {
    19
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 19);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 38);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 57);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 76);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 95);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 114);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 133);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 152);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 171);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 190);
    }

}
