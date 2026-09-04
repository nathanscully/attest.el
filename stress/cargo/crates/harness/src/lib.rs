use proc_macro::TokenStream;

/// Attribute macro standing in for `tokio::test`, arguments and all.
#[proc_macro_attribute]
pub fn test(_args: TokenStream, item: TokenStream) -> TokenStream {
    let mut out: TokenStream = "#[test]".parse().unwrap();
    out.extend(item);
    out
}
