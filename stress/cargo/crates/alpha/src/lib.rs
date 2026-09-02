pub mod a;
pub mod bulk;
pub mod many;

/// Adds two numbers.
///
/// ```
/// assert_eq!(alpha::add(1, 2), 3);
/// ```
pub fn add(x: i32, y: i32) -> i32 {
    x + y
}

#[cfg(test)]
mod tests {
    use super::add;

    #[test]
    fn adds() {
        assert_eq!(add(1, 2), 3);
    }

    #[test]
    fn fails_on_purpose() {
        let x = 2;
        assert_eq!(x, 3, "x should be three");
    }

    #[test]
    #[should_panic(expected = "boom")]
    fn expected_panic() {
        panic!("boom");
    }

    #[test]
    #[ignore = "slow"]
    fn ignored_one() {
        assert!(true);
    }

    #[test]
    fn same() {
        assert!(true);
    }

    #[test]
    fn returns_result() -> Result<(), String> {
        Err("result-based failure".to_string())
    }

    #[test]
    fn panics_deep() {
        fn deep(n: u32) {
            if n == 0 {
                panic!("bottom of a deep stack");
            }
            deep(n - 1);
        }
        deep(40);
    }

    #[test]
    fn prints_then_fails() {
        println!("captured stdout line one");
        eprintln!("captured stderr line");
        assert_eq!(1, 2);
    }
}
