pub fn value() -> i32 {
    23
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 23);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 46);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 69);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 92);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 115);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 138);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 161);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 184);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 207);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 230);
    }

}
