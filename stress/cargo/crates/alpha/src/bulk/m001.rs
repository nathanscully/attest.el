pub fn value() -> i32 {
    1
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 1);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 2);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 3);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 4);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 5);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 6);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 7);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 8);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 9);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 10);
    }

}
