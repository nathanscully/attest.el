pub fn value() -> i32 {
    20
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 20);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 40);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 60);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 80);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 100);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 120);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 140);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 160);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 180);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 200);
    }

}
