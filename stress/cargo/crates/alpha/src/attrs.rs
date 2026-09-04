pub fn quadruple(x: i32) -> i32 {
    x * 4
}

#[cfg(test)]
mod tests {
    use super::quadruple;

    #[harness::test(flavor = "multi_thread")]
    fn attribute_with_arguments() {
        assert_eq!(quadruple(1), 4);
    }

    #[harness::test(flavor = "multi_thread", worker_threads = 2)]
    fn attribute_with_two_arguments() {
        assert_eq!(quadruple(2), 8);
    }

    #[harness::test]
    fn namespaced_attribute() {
        assert_eq!(quadruple(3), 12);
    }

    #[test]
    fn plain_attribute() {
        assert_eq!(quadruple(0), 0);
    }
}
