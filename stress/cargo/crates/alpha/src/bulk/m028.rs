pub fn value() -> i32 {
    28
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 28);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 56);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 84);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 112);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 140);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 168);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 196);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 225);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 252);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 280);
    }

}
