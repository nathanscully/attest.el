pub fn value() -> i32 {
    22
}

#[cfg(test)]
mod tests {
    use super::value;

    #[test]
    fn check_01() {
        assert_eq!(value() * 1, 22);
    }

    #[test]
    fn check_02() {
        assert_eq!(value() * 2, 44);
    }

    #[test]
    fn check_03() {
        assert_eq!(value() * 3, 66);
    }

    #[test]
    fn check_04() {
        assert_eq!(value() * 4, 88);
    }

    #[test]
    fn check_05() {
        assert_eq!(value() * 5, 110);
    }

    #[test]
    fn check_06() {
        assert_eq!(value() * 6, 132);
    }

    #[test]
    fn check_07() {
        assert_eq!(value() * 7, 154);
    }

    #[test]
    fn check_08() {
        assert_eq!(value() * 8, 176);
    }

    #[test]
    fn check_09() {
        assert_eq!(value() * 9, 198);
    }

    #[test]
    fn check_10() {
        assert_eq!(value() * 10, 220);
    }

}
