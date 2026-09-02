pub fn value() -> i32 {
    14
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 14);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 28);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 42);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 56);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 70);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 84);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 98);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 113);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 126);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 140);
    }

}
