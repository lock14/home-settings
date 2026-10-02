; Supersede upstream elixir injections to prevent unconditional Markdown injection
; into @moduledoc / @doc strings (keeping docstrings in pure Solarized Cyan @string).

((comment) @injection.content
  (#set! injection.language "comment"))

; Regex sigils (~r / ~R)
(sigil
  (sigil_name) @_sigil_name
  (quoted_content) @injection.content
  (#any-of? @_sigil_name "r" "R")
  (#set! injection.language "regex"))
