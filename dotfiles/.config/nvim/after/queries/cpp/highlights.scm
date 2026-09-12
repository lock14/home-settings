;; extends
(preproc_defined "defined" @keyword)

;; Highlight custom type identifiers inside sizeof(...) as @type
(sizeof_expression
  (parenthesized_expression
    (identifier) @type
    (#match? @type "^([A-Z]|.+_t$)")))
