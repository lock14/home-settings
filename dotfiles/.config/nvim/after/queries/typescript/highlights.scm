;; extends

; Built-in global environment singletons (process, globalThis) match console, window, document in Solarized Magenta (#D33682)
((identifier) @variable.builtin
  (#any-of? @variable.builtin "process" "globalThis"))
