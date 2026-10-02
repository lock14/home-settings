;; extends

; =============================================================================
; Solarized Dark TrueColor Overrides for GNU Make (Exact 1:1 Parity with Bat)
; =============================================================================

; 1. Special Built-in Targets (.PHONY, .DELETE_ON_ERROR, .ONESHELL, .SILENT, etc.)
; Highlighted in Solarized Green (@keyword #859900)
(rule
  (targets
    (word) @keyword
    (#any-of? @keyword
      ".DEFAULT" ".SUFFIXES" ".DELETE_ON_ERROR" ".EXPORT_ALL_VARIABLES" ".IGNORE" ".INTERMEDIATE"
      ".LOW_RESOLUTION_TIME" ".NOTPARALLEL" ".ONESHELL" ".PHONY" ".POSIX" ".PRECIOUS" ".SECONDARY"
      ".SECONDEXPANSION" ".SILENT"))
  (#set! priority 125))

; Pattern Rule Targets ($(BUILD_DIR)/%.o:) in Solarized Blue (@function #268BD2)
(rule
  (targets
    (concatenation
      (word) @function))
  (#set! priority 115))

; Prerequisite Target References (including after .PHONY:) in Calm Base0 Grey (@variable #839496)
(rule
  (prerequisites
    (word) @variable)
  (#set! priority 120))

; 2. Export & Override Directives in Solarized Green (@keyword #859900)
([
  "export"
  "unexport"
] @keyword
  (#set! priority 115))

; 3. Recipe Prefix Modifiers (@, -, +) in Solarized Orange (@keyword.directive #CB4B16)
(recipe_line
  [
    "@"
    "-"
    "+"
  ] @keyword.directive
  (#set! priority 130))

; 4. Automatic Variables ($@, $<, $^, $*, $?, $+, $|) in Solarized Magenta (@constant.builtin #D33682)
((automatic_variable) @constant.builtin
  (#set! priority 130))

(automatic_variable
  "$" @constant.builtin
  _ @constant.builtin
  (#set! priority 135))

; 5. Variable Declarations & References
; Reset upstream @string.special.symbol / @string (Cyan) to calm Base0 Grey (@variable #839496)
; for lowercase variables, and Solarized Magenta (@constant #D33682) for ALL_CAPS constants.
(variable_assignment
  name: (word) @variable
  (#set! priority 115))

(shell_assignment
  name: (word) @variable
  (#set! priority 115))

(define_directive
  name: (word) @variable
  (#set! priority 115))

; Keep variable & function expansion delimiters ($(, ${, ), }) in calm Base0 Grey (@punctuation.special #839496)
; even inside double-quoted recipe strings where injected bash applies @string at priority 100
([
  (variable_reference)
  (substitution_reference)
] @punctuation.special
  (#set! priority 115))

(shell_function
  [
    "$"
    "("
    ")"
  ] @punctuation.special
  "shell" @function.builtin
  (#set! priority 120))

(function_call
  [
    "$"
    "("
    ")"
  ] @punctuation.special
  (#set! priority 120))

(variable_reference
  (word) @variable
  (#set! priority 120))

(variable_assignment
  name: (word) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]+$")
  (#set! priority 125))

(shell_assignment
  name: (word) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]+$")
  (#set! priority 125))

(define_directive
  name: (word) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]+$")
  (#set! priority 125))

(variable_reference
  (word) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]+$")
  (#set! priority 125))

(export_directive
  variables: (list
    (word) @constant
    (#lua-match? @constant "^[A-Z][A-Z0-9_]+$"))
  (#set! priority 125))

(ifdef_directive
  variable: (word) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]+$")
  (#set! priority 125))

(ifndef_directive
  variable: (word) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]+$")
  (#set! priority 125))

; Keep built-in Make variables (.DEFAULT_GOAL, .SHELLFLAGS, SHELL, MAKEFLAGS) in Solarized Magenta (#D33682)
(variable_assignment
  name: (word) @variable.builtin
  (#any-of? @variable.builtin
    ".DEFAULT_GOAL" ".EXTRA_PREREQS" ".FEATURES" ".INCLUDE_DIRS" ".RECIPEPREFIX" ".SHELLFLAGS"
    ".VARIABLES" "MAKEARGS" "MAKEFILE_LIST" "MAKEFLAGS" "MAKE_RESTARTS" "MAKE_TERMERR"
    "MAKE_TERMOUT" "SHELL")
  (#set! priority 130))

; 6. Numeric Values & Version Literals in Solarized Magenta (@number #D33682)
((word) @number
  (#lua-match? @number "^[0-9]+$")
  (#set! priority 120))

((text) @number
  (#lua-match? @number "^[0-9]+$")
  (#set! priority 120))

((text) @number.float
  (#lua-match? @number.float "^[0-9]+%.[0-9.]+$")
  (#set! priority 120))
