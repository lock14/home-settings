;; CSS Tree-sitter Base Query for Converged Ergonomic Solarized Scheme
;; Supersedes upstream base queries to eliminate greedy selectors and unstyled at-rules

;; At-rules (@layer, @font-face, @keyframes, @media, @container, @supports) -> Solarized Orange (#CB4B16)
[
  (at_keyword)
  "@media"
  "@charset"
  "@namespace"
  "@supports"
  "@keyframes"
  "@scope"
  "@container"
] @keyword.directive

"@import" @keyword.import

;; Keyframes step selectors
[
  (to)
  (from)
] @keyword

;; Comments
(comment) @comment

;; Tag & Wildcard selectors -> Solarized Blue (#268BD2)
((tag_name) @tag (#set! priority 130))
((universal_selector) @tag (#set! priority 130))

;; Class selectors (.class-name) -> Solarized Blue (#268BD2)
((class_name) @type.css (#set! priority 130))

;; ID selectors (#id-name) -> Solarized Blue (#268BD2)
((id_name) @type.css (#set! priority 130))
((id_selector) @type.css (#set! priority 130))

;; Pseudo-classes & Pseudo-elements -> Solarized Violet (#6C71C4)
((pseudo_class_selector (class_name) @attribute) (#set! priority 130))
((pseudo_element_selector "::" (tag_name) @attribute) (#set! priority 130))

;; Nesting parent selector '&' -> calm Base0 Grey (#839496)
((nesting_selector) @operator (#set! priority 130))

;; Combinators and operators
[
  "~"
  ">"
  "+"
  "-"
  "/"
  "="
  "^="
  "|="
  "~="
  "$="
  "*="
] @operator

(binary_expression ["+" "-" "*" "/"] @operator)

[
  "and"
  "or"
  "not"
  "only"
] @keyword.operator

(important) @keyword.modifier

;; Property names -> Solarized Green (#859900)
((property_name) @property.css (#set! priority 130))

;; Property values & identifiers -> Calm Base0 Grey (#839496)
((plain_value) @variable.css (#set! priority 130))

;; Custom properties (--*) -> Calm Base0 Grey (#839496)
((property_name) @variable.css
  (#lua-match? @variable.css "^[-][-]")
  (#set! priority 135))

((plain_value) @variable.css
  (#lua-match? @variable.css "^[-][-]")
  (#set! priority 135))

;; Function calls -> Calm Base0 Grey (#839496)
((function_name) @function.call.css (#set! priority 130))
(style_query "style" @function.call.css (#set! priority 130))
(selector_query "selector" @function.call.css (#set! priority 130))

;; Container queries & features -> Calm Base0 Grey (#839496)
((container_name) @variable.css (#set! priority 130))
((feature_name) @variable.css (#set! priority 130))

;; Attribute selectors ([data-status="healthy"])
((attribute_name) @tag.attribute (#set! priority 130))
(attribute_selector ["[" "]"] @punctuation.delimiter (#set! priority 130))
(attribute_selector ["=" "^=" "$=" "*=" "~=" "|="] @operator (#set! priority 130))
(attribute_selector (plain_value) @string (#set! priority 130))

;; Strings
((string_value) @string (#set! priority 130))

;; Hex color constants -> Solarized Magenta (#D33682)
((color_value) @string.special.css (#set! priority 130))

;; Numbers and units
(integer_value) @number
(float_value) @number.float
((unit) @type.builtin.css (#set! priority 130))

;; Delimiters & punctuation -> Calm Base0 Grey
[
  ","
  "."
  ":"
  "::"
  ";"
  "{"
  "}"
  "["
  "]"
  "("
  ")"
] @punctuation.delimiter
