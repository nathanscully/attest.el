pub fn value() -> i32 {
    29
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 29);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 58);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 87);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 116);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 145);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 174);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 203);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 232);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 261);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 290);
    }

}
