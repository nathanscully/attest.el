pub fn value() -> i32 {
    11
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 11);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 22);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 33);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 44);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 55);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 66);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 77);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 88);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 99);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 110);
    }

}
