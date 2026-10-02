;; extends

;; Map NULL to built-in constant (Solarized Magenta #D33682) matching nil/None/nullptr
(keyword_null) @constant.builtin

;; Map table alias qualifiers in field expressions (e.g. a.account_id, s.aggregate_spend)
;; to @variable (Base0 Grey #839496) following Principle 5 (Declarations vs. Qualifiers)
(field
  (object_reference
    name: (identifier) @variable))

;; Map index names in CREATE INDEX statements to @type (Solarized Base1 #93A1A1)
(create_index
  (identifier) @type)

;; Map CTE alias names in WITH statements to @type
(cte
  (identifier) @type)

;; Map END in CASE ... END expressions to @keyword.conditional (Solarized Yellow #B58900) matching CASE/WHEN/THEN/ELSE
((keyword_end) @keyword.conditional
  (#set! "priority" 105))

;; Map INTERVAL literal payload ('30 days') to @string (Solarized Cyan #2AA198) while keeping INTERVAL keyword as @type.builtin
(interval) @string
(interval
  (keyword_interval) @type.builtin
  (#set! "priority" 105))


