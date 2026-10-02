;; extends

; =============================================================================
; Solarized Dark C# Highlighting Architecture
; =============================================================================
; Enforce the strict Solarized Dark hierarchy:
;   - Violet (#6C71C4): using directives, namespace declarations, and unified [Attribute] blocks
;   - Blue (#268BD2):   Method and constructor declarations
;   - Green (#859900):  Structural keywords (class, record, struct, interface, enum, public, sealed,
;                       readonly, const, async, get, set, init, where) and primitive types
;   - Yellow (#B58900): Control flow (if, else, switch, case, when, for, foreach, in, while,
;                       do, return, break, continue, try, catch, finally, throw, await, yield)
;   - Cyan (#2AA198):   String literals, verbatim/raw strings, and interpolation format specifiers
;   - Magenta (#D33682): Numeric literals, booleans, null, default, this, base, discard (_),
;                       enum declaration members, and SCREAMING_SNAKE_CASE constants
;   - Base0 (#839496):  User types, properties, variables, method calls, and interpolated expressions
; =============================================================================

; Base capture for identifiers so variables inside $"..." string interpolations
; do not fall through (via @none) to @string Cyan (Rule 35)
((identifier) @variable
  (#set! priority 95))

; Unify attribute brackets and attribute names in Violet (Rule 11: No Token Fracturing)
(attribute_list
  [
    "["
    "]"
  ] @attribute
  (#set! priority 115))

(attribute
  name: (identifier) @attribute
  (#set! priority 115))

(attribute
  name: (qualified_name) @attribute
  (#set! priority 115))

; Foreach iteration keyword "in" is Yellow control flow
(foreach_statement
  "in" @keyword.repeat
  (#set! priority 115))

; Generic type constraint "where" is a structural type modifier (Green), not runtime control flow
(type_parameter_constraints_clause
  "where" @keyword
  (#set! priority 115))

; Discard pattern "_" and default literal expressions in Magenta
((discard) @constant.builtin
  (#set! priority 115))

((default_expression) @constant.builtin
  (#set! priority 115))

; SCREAMING_SNAKE_CASE constants in Magenta
((identifier) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]+$")
  (#set! priority 115))

; Generic method invocations (.ToList<T>(), .Empty<T>()) are calls (Base0 Grey), not declarations (Blue)
(invocation_expression
  function: (member_access_expression
    name: (generic_name
      (identifier) @function.method.call
      (#set! priority 115))))

(invocation_expression
  function: (generic_name
    (identifier) @function.call
    (#set! priority 115)))

; Prevent @none transparent fallthrough inside $"..." string interpolations (Rule 35)
(interpolation
  (interpolation_brace) @punctuation.special
  (#set! priority 115))

((interpolation_format_clause) @string.special
  (#set! priority 115))
