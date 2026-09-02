pub fn value() -> i32 {
    5
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 5);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 10);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 15);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 20);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 25);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 30);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 35);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 40);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 45);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 50);
    }

}
