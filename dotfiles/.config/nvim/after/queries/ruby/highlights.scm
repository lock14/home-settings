;; extends

; =============================================================================
; Solarized Dark Ruby Highlighting Architecture
; =============================================================================
; Enforce the strict Solarized Dark hierarchy:
;   - Violet (#6C71C4): require / require_relative / load and module declaration names
;   - Blue (#268BD2):   Method declarations (def <name>, def self.<name>)
;   - Green (#859900):  Structural keywords (module, class, def, end, do, begin, include,
;                       extend, prepend, attr_reader, attr_writer, attr_accessor,
;                       private, protected, public, module_function, alias)
;   - Yellow (#B58900): Control flow (if, elsif, else, unless, case, when, in, while, until,
;                       for, return, break, next, redo, retry, yield, rescue, ensure, raise, super)
;   - Cyan (#2AA198):   String literals and regex literals
;   - Magenta (#D33682): :symbols, numeric literals, booleans, nil, self, and SCREAMING_SNAKE_CASE constants
;   - Base0 (#839496):  Classes/types, @instance_vars, @@class_vars, hash_key_symbols (key:),
;                       local variables, method calls, and #{...} interpolated expressions
; =============================================================================

; Base capture for identifiers so variables inside #{...} string interpolations
; do not fall through to @string Cyan (Rule 35)
((identifier) @variable
  (#set! priority 95))

; Module declaration name in Violet
(module
  name: (constant) @module
  (#set! priority 115))

; Structural mixin & attribute macros in Green
((identifier) @keyword.modifier
  (#any-of? @keyword.modifier
    "include" "extend" "prepend"
    "attr_reader" "attr_writer" "attr_accessor"
    "private" "protected" "public" "module_function")
  (#set! priority 115))

; Hash/keyword argument symbol keys (key:) in calm Base0 Grey, isolating :symbol literals in Magenta
((hash_key_symbol) @variable.member
  (#set! priority 115))

; Keep block-closing "end" uniformly Green across all constructs (if, case, def, class, module, do, begin)
("end" @keyword
  (#set! priority 115))

; SCREAMING_SNAKE_CASE constants in Magenta
((constant) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]+$")
  (#set! priority 115))
