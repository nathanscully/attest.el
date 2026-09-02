use alpha::add;

#[test]
fn integration_adds() {
    assert_eq!(add(2, 2), 4);
}

#[test]
fn integration_fails() {
    assert_eq!(add(2, 2), 5);
}

#[test]
fn same() {
    assert!(true);
}
