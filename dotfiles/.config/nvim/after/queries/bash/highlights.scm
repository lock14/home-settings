;; extends

; Authentic Solarized Dark TrueColor Tree-sitter query overrides for Bash / Shell

; Trap signal sentinels as constants (Solarized Magenta #d33682)
(command
  name: (command_name
    (word) @_command)
  argument: (word) @constant.builtin
  (#eq? @_command "trap")
  (#any-of? @constant.builtin "EXIT" "DEBUG" "RETURN" "ERR"))

(command
  name: (command_name
    (word) @_command)
  argument: (word) @constant.builtin
  (#any-of? @_command "trap" "kill")
  (#lua-match? @constant.builtin "^SIG[A-Z0-9]+$"))

; Positional parameters ($0, $1, $2, ...) as built-in constants (Solarized Magenta #d33682)
((simple_expansion
  (variable_name) @constant.builtin)
  (#lua-match? @constant.builtin "^[0-9]+$"))

; Heredoc delimiters (EOF) in Solarized Green (@keyword #859900) matching bat
[
  (heredoc_start)
  (heredoc_end)
] @keyword
(#set! "priority" 105)

; Parameter expansion default/fallback payload inside "${VAR:-default}" in calm Base0 Grey (@variable #839496)
((expansion) @variable
  (#set! "priority" 101))

; Preserve ALL_CAPS constant highlighting inside parameter expansions (Solarized Magenta @constant #d33682)
((variable_name) @constant
  (#lua-match? @constant "^[A-Z][A-Z_0-9]*$")
  (#set! "priority" 105))

; Unquoted associative array subscript keys ([nginx]="edge") in calm Base0 Grey (@variable #839496) matching bat,
; while preserving [@] and [*] special array subscripts in Solarized Cyan (@character.special #2aa198)
(subscript
  index: (word) @variable
  (#not-any-of? @variable "@" "*")
  (#set! "priority" 105))
(subscript
  index: (word) @character.special
  (#any-of? @character.special "@" "*")
  (#set! "priority" 110))
(array
  (concatenation
    (word) @variable
    (#set! "priority" 105)))

