pub fn scan(s: &str) -> usize {
    s.split_whitespace().count()
}

#[cfg(test)]
mod tests {
    #[test]
    fn counts_words() {
        assert_eq!(super::scan("a b"), 2);
    }
}
