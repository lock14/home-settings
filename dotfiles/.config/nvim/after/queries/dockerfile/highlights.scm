;; extends

; =============================================================================
; Solarized Dark TrueColor Overrides for Dockerfile / Containerfile
; =============================================================================

; 1. BuildKit Parser Directives (# syntax=..., # escape=...) in Solarized Orange (#CB4B16)
((comment) @keyword.directive
  (#lua-match? @keyword.directive "^#%s*syntax%s*=")
  (#set! priority 120))

((comment) @keyword.directive
  (#lua-match? @keyword.directive "^#%s*escape%s*=")
  (#set! priority 120))

; 2. Multi-Stage Build Stage Alias (FROM ... AS builder) in Solarized Blue (#268BD2)
(from_instruction
  as: (image_alias) @function
  (#set! priority 115))

; 3. Instruction Flags (--mount=..., --from=..., --chown=..., --interval=...) in Calm Base0 Grey (#839496)
([
  (param)
  (mount_param)
  (mount_param_param)
] @variable.parameter
  (#set! priority 115))

; 4. Quoted & JSON Array Strings in Solarized Cyan (#2AA198)
([
  (double_quoted_string)
  (single_quoted_string)
  (json_string)
] @string
  (#set! priority 115))

; Variable Expansions (${VAR}, $VAR) inside and outside double-quoted strings:
; delimiters in calm Base0 Grey (#839496), ALL_CAPS variables in Solarized Magenta (#D33682)
(expansion
  [
    "$"
    "{"
    "}"
  ] @punctuation.special
  (#set! priority 120))

(expansion
  (variable) @variable
  (#set! priority 120))

((variable) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]+$")
  (#set! priority 125))

; 5. ALL_CAPS Constants, Booleans, and Numeric Values in Solarized Magenta (#D33682)
((unquoted_string) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]+$")
  (#set! priority 115))

((unquoted_string) @boolean
  (#any-of? @boolean "true" "false")
  (#set! priority 115))

((unquoted_string) @number
  (#lua-match? @number "^[0-9]+$")
  (#set! priority 115))

((unquoted_string) @number.float
  (#lua-match? @number.float "^[0-9]+%.[0-9.]+$")
  (#set! priority 115))

; Keep EXPOSE protocol suffix (/tcp, /udp) in calm Base0 Grey (#839496) while port number is Magenta
(expose_port
  [
    "/tcp"
    "/udp"
  ] @variable
  (#set! priority 115))

; Line continuation backslashes in calm Base0 Grey (#839496)
((line_continuation) @punctuation.special
  (#set! priority 115))
