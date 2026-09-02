pub fn thrice(x: i32) -> i32 {
    x * 3
}

#[cfg(test)]
mod tests {
    use super::thrice;

    #[test]
    fn same() {
        assert_eq!(thrice(1), 3);
    }

    mod inner {
        use super::super::thrice;

        #[test]
        fn nested_module_test() {
            assert_eq!(thrice(2), 6);
        }

        #[test]
        fn nested_module_fails() {
            assert_eq!(thrice(2), 7);
        }
    }
}

#[test]
fn outside_tests_module() {
    assert_eq!(thrice(0), 0);
}
