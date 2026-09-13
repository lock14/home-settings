;; extends

;; Unify Rust attributes (#[inline], #[derive(...)]) as Solarized Orange (@attribute)
(attribute
  (identifier) @attribute)

;; Unify Rust lifetimes ('a, 'static, '_) as Solarized Green (@keyword.modifier)
(lifetime
  (identifier) @keyword.modifier)
