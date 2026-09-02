pub fn value() -> i32 {
    26
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 26);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 52);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 78);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 104);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 130);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 156);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 182);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 208);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 234);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 260);
    }

}
