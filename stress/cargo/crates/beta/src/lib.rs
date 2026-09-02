pub fn sub(x: i32, y: i32) -> i32 {
    x - y
}

#[cfg(test)]
mod tests {
    use super::sub;

    #[test]
    fn adds() {
        assert_eq!(sub(3, 1), 2);
    }

    #[test]
    fn beta_fails() {
        assert_eq!(sub(3, 1), 3);
    }
}
