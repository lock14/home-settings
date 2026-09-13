;; extends

;; Reset any root variable expression (e.g. aws_s3_bucket in aws_s3_bucket.lake.arn)
;; to @variable (calm Base0 Grey #839496), fixing the upstream HCL query leak
(variable_expr
  (identifier) @variable)

;; Map reserved Terraform scope accessors (var, local, terraform, data, module, etc.)
;; to @keyword (Solarized Green #859900) matching their block declaration counterparts
((variable_expr
   (identifier) @keyword)
 (#any-of? @keyword "data" "var" "local" "module" "output" "path" "terraform" "count" "each"))

;; Map primitive types (string, number, bool, etc.) to @type.builtin (Solarized Yellow #B58900)
((variable_expr
   (identifier) @type.builtin)
 (#any-of? @type.builtin "bool" "string" "number" "object" "tuple" "list" "map" "set" "any"))

;; Override terraform.workspace attribute to @variable.member (Base0 Grey #839496)
(expression
  (variable_expr
    (identifier) @keyword
    (#eq? @keyword "terraform"))
  (get_attr
    (identifier) @variable.member
    (#eq? @variable.member "workspace")))

;; Map interpolation and directive delimiters to @punctuation.bracket (Base0 Grey #839496)
;; adhering to Principle 10 and preventing chromatic collision with green keyword 'var'
[
  (template_interpolation_start)
  (template_interpolation_end)
  (template_directive_start)
  (template_directive_end)
] @punctuation.bracket

;; Map ternary operator ? to @operator in calm Base0 Grey
("?" @operator)
