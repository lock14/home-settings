;; extends
(preproc_defined "defined" @keyword)

;; Highlight custom type identifiers inside sizeof(...) as @type
(sizeof_expression
  (parenthesized_expression
    (identifier) @type
    (#match? @type "^([A-Z]|.+_t$)")))

;; Switch default branch -> Yellow (@keyword.conditional)
(case_statement
  "default" @keyword.conditional
  (#set! "priority" 105))

;; C23 attributes: [[nodiscard]], [[maybe_unused]] -> unified Violet (@attribute)
(attribute_declaration
  "[[" @attribute
  "]]" @attribute
  (#set! "priority" 105))
(attribute
  name: (identifier) @attribute
  (#set! "priority" 105))

;; Preprocessor #include directive -> Solarized Orange (@keyword.directive #CB4B16) matching bat and cInclude
(preproc_include
  "#include" @keyword.directive
  (#set! "priority" 105))

;; C23 static_assert keyword -> Solarized Green (@keyword #859900) matching bat
((identifier) @keyword
  (#eq? @keyword "static_assert")
  (#set! "priority" 105))
