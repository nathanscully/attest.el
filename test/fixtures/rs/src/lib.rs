pub mod scanner;

pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adds() {
        assert_eq!(add(1, 1), 2);
    }

    #[test]
    fn fails_on_purpose() {
        let x = 2;
        assert_eq!(x, 3, "x should be three");
    }

    #[test]
    #[ignore]
    fn ignored_one() {}

    #[test]
    #[should_panic]
    fn panics() {
        panic!("boom");
    }
}
