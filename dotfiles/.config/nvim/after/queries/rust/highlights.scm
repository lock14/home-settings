;; extends

;; Unify Rust attributes (#[inline], #[derive(...)]) as Solarized Violet (@attribute #6c71c4)
(attribute
  (identifier) @attribute)

(attribute_item
  [
    "#"
    "["
    "]"
  ] @attribute)

(inner_attribute_item
  [
    "#"
    "!"
    "["
    "]"
  ] @attribute)

;; Unify Rust lifetimes ('a, 'static, '_) as Solarized Green (@keyword.modifier)
(lifetime
  (identifier) @keyword.modifier)
