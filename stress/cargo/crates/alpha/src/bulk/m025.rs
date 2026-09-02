pub fn value() -> i32 {
    25
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 25);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 50);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 75);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 100);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 125);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 150);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 175);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 200);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 225);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 250);
    }

}
