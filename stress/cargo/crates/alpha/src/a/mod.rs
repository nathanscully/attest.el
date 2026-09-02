pub mod b;

pub fn twice(x: i32) -> i32 {
    x * 2
}

#[cfg(test)]
mod tests {
    use super::twice;

    #[test]
    fn same() {
        assert_eq!(twice(2), 4);
    }

    #[test]
    fn doubles() {
        assert_eq!(twice(3), 6);
    }
}
