;; extends
;; Properties Tree-sitter Overrides for Converged Ergonomic Solarized Scheme

((key) @property.properties (#set! priority 130))
((value) @boolean (#any-of? @boolean "true" "false") (#set! priority 130))
((value) @number (#lua-match? @number "^%d+$") (#set! priority 130))
((value) @number.float (#lua-match? @number.float "^%d+%.%d+$") (#set! priority 130))
((index) @number (#lua-match? @number "^%d+$") (#set! priority 130))
(substitution (key) @variable.properties (#set! priority 135))
(escape) @string.escape
(property ["=" ":"] @operator)
