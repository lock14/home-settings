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

