;; extends

; =============================================================================
; Solarized Dark TrueColor Overrides for Lua (Exact 1:1 Parity with Bat)
; =============================================================================

; 1. Control Flow & Loop Keywords (Solarized Yellow #B58900)
("in" @keyword.repeat
  (#set! priority 110))

("goto" @keyword.return
  (#set! priority 110))

((break_statement) @keyword.repeat
  (#set! priority 110))

(do_statement
  [
    "do"
    "end"
  ] @keyword.repeat
  (#set! priority 110))

; 2. Lua 5.4 Variable Attributes (<const>, <close>) Unified in Solarized Violet (#6C71C4)
(attribute
  "<" @attribute
  (identifier) @attribute
  ">" @attribute
  (#set! priority 120))

; 3. Built-in Global Environment Singletons (_G, _VERSION) in Solarized Magenta (#D33682)
((identifier) @constant.builtin
  (#any-of? @constant.builtin "_G" "_VERSION")
  (#set! priority 120))

; 4. Standard Library Table Qualifiers (string, math, table, io, coroutine, etc.)
; Remain in calm Base0 Grey (@variable #839496) per Pillar IV (No Chromatic Noise on Scope Qualifiers)
((identifier) @variable
  (#any-of? @variable
    "coroutine" "debug" "io" "jit" "math" "os" "package" "string" "table" "utf8")
  (#set! priority 120))

; 5. Single-Letter Module Table Identifiers (local M = {}) vs. ALL_CAPS Constants
; Single-letter uppercase module tables remain calm Base0 Grey (@variable #839496)
((identifier) @variable
  (#lua-match? @variable "^[A-Z]$")
  (#set! priority 115))

; Multi-character SCREAMING_SNAKE_CASE constants (including table fields like _G.SOLARIZED_DEBUG)
; are Solarized Magenta (@constant #D33682)
((identifier) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]+$")
  (#set! priority 120))

; 6. Routine Invocations (Calm Base0 Grey @function.call #839496)
; Supersedes solarized.nvim's after/queries/lua/highlights.scm priority 130 @function rule
(function_call
  name: (identifier) @function.call
  (#set! priority 135))

; 7. Metamethods (__index, __tostring, __call, __close, etc.) in Solarized Magenta (#D33682)
((identifier) @constant.builtin
  (#any-of? @constant.builtin
    "__add" "__band" "__bnot" "__bor" "__bxor" "__call" "__close" "__concat" "__div"
    "__eq" "__gc" "__idiv" "__index" "__le" "__len" "__lt" "__metatable" "__mod"
    "__mode" "__mul" "__name" "__newindex" "__pairs" "__pow" "__shl" "__shr" "__sub"
    "__tostring" "__unm")
  (#set! priority 140))

; 8. String Pattern Arguments (Keep quoted strings unified in Solarized Cyan #2AA198)
(string
  content: (string_content) @string
  (#set! priority 135))

((escape_sequence) @string.escape
  (#set! priority 140))
