pub fn other() -> usize {
    1
}

#[cfg(test)]
mod tests {
    #[test]
    fn not_in_scanner() {
        assert_eq!(super::other(), 1);
    }
}
