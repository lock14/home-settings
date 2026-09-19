;; Properties Tree-sitter Base Query for Converged Ergonomic Solarized Scheme
;; Supersedes upstream base queries to enforce Solarized Green keys, Magenta numbers/booleans, and Base0 variable interpolations

;; Comments -> Solarized Base01 Dim (#586E75)
(comment) @comment @spell

;; Property keys -> Solarized Green (#859900)
((key) @property.properties (#set! priority 130))

;; Boolean values -> Solarized Magenta (#D33682)
((value) @boolean
  (#any-of? @boolean "true" "false")
  (#set! priority 130))

;; Integer numbers -> Solarized Magenta (#D33682)
((value) @number
  (#lua-match? @number "^%d+$")
  (#set! priority 130))

;; Float numbers -> Solarized Magenta (#D33682)
((value) @number.float
  (#lua-match? @number.float "^%d+%.%d+$")
  (#set! priority 130))

((index) @number
  (#lua-match? @number "^%d+$")
  (#set! priority 130))

;; Escapes -> Solarized Violet (#6C71C4)
(escape) @string.escape

;; Variable substitutions: ${var.name}
(substitution
  [
    "${"
    "}"
  ] @punctuation.special)

(substitution
  (key) @variable.properties
  (#set! priority 135))

(substitution
  ":" @punctuation.special)

;; Delimiters & separators -> Calm Base0 Grey (#839496)
(property
  [
    "="
    ":"
  ] @operator)

[
  "["
  "]"
] @punctuation.bracket

[
  "."
  "\\"
] @punctuation.delimiter

;; Default string values -> Solarized Cyan (#2AA198)
(value) @string
