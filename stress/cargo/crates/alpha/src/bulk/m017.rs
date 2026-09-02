pub fn value() -> i32 {
    17
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 17);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 34);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 51);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 68);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 85);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 102);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 119);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 136);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 153);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 170);
    }

}
