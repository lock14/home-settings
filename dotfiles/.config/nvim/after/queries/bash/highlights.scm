; inherits: bash

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
