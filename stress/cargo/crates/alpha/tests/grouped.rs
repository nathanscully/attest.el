mod helpers {
    #[test]
    fn in_module() {
        assert_eq!(alpha::a::twice(1), 2);
    }

    mod deeper {
        #[test]
        fn in_nested_module() {
            assert_eq!(alpha::a::b::thrice(1), 3);
        }
    }
}

#[test]
fn top_level() {
    assert!(true);
}
