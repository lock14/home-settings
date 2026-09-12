;; extends
(preproc_defined "defined" @keyword)

;; Highlight custom type identifiers inside sizeof(...) as @type
(sizeof_expression
  (parenthesized_expression
    (identifier) @type
    (#match? @type "^([A-Z]|.+_t$)")))

;; Constrained concept type parameter in template: template <Printable T>
(template_parameter_list
  (parameter_declaration
    type: (type_identifier)
    declarator: (identifier) @type))

;; Variadic constrained concept parameter: template <Printable... Args>
(template_parameter_list
  (variadic_parameter_declaration
    type: (type_identifier)
    declarator: (variadic_declarator (identifier) @type)))

