;; extends

; =============================================================================
; Solarized Dark Zig Highlighting Architecture
; =============================================================================
; Enforce the strict Solarized Dark hierarchy:
;   - Violet (#6C71C4): @import / @cImport builtins and imported module bindings
;   - Blue (#268BD2):   Function declarations (fn <name>, including generic type constructors)
;   - Green (#859900):  Structural declarations (const, var, struct, enum, union, error, pub, comptime)
;                       and built-in primitive types (u8, u16, u32, u64, usize, f64, bool, void, type)
;   - Yellow (#B58900): Control flow & cleanup execution pathways (if, else, switch, while, for,
;                       return, break, continue, try, catch, defer, errdefer)
;   - Cyan (#2AA198):   String literals and character literals
;   - Magenta (#D33682): Numeric literals, booleans, null, undefined, self, error set members,
;                       enum shorthand literals (.info, .critical), and SCREAMING_SNAKE_CASE constants
;   - Base0 (#839496):  User types, struct field initializers (.id = 1), identifiers, and calls
; =============================================================================

; Cleanup execution pathways belong to Yellow control flow alongside try/catch
[
  "defer"
  "errdefer"
] @keyword.conditional
(#set! priority 115)

; Ensure @import and @cImport builtins are always Violet
((builtin_identifier) @keyword.import
  (#any-of? @keyword.import "@import" "@cImport")
  (#set! priority 115))

; Ensure all fn declaration names (including generic comptime type functions) are Blue
(function_declaration
  name: (identifier) @function
  (#set! priority 115))

; Receiver identifier "self" in Magenta (#D33682)
((identifier) @variable.builtin
  (#eq? @variable.builtin "self")
  (#set! priority 115))

; SCREAMING_SNAKE_CASE constants in Magenta
((identifier) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]+$")
  (#set! priority 115))
