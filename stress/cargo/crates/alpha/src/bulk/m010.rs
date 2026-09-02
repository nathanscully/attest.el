pub fn value() -> i32 {
    10
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 10);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 20);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 30);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 40);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 50);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 60);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 70);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 80);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 90);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 100);
    }

}
