pub fn value() -> i32 {
    13
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 13);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 26);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 39);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 52);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 65);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 78);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 91);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 104);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 117);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 130);
    }

}
