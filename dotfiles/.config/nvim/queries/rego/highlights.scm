;; Open Policy Agent (OPA Rego v1) Tree-sitter Base Query
;; Supersedes upstream base queries to enforce the Universal Semantic Color Contract:
;; - Package Keyword (package) -> Solarized Green (@keyword #859900)
;; - Import Keyword (import) -> Solarized Violet (@keyword.import #6C71C4)
;; - Package & Import Module Paths / Aliases -> Solarized Violet (@module #6C71C4)
;; - Structural & Query Keywords (default, some, contains, with, as, in, not) -> Solarized Green (#859900)
;; - Conditional & Quantifier Control Flow (if, else, every) -> Solarized Yellow (#B58900)
;; - Rule & Function Declarations (allow, violations, is_rate_limited) -> Solarized Blue (@function #268BD2)
;; - Built-in & Helper Function Calls (sprintf, count, regex.match) -> Calm Base0 Grey (@function.call #839496)
;; - ALL_CAPS Constants, Numbers (with unified sign), Booleans, and null -> Solarized Magenta (#D33682)
;; - Quoted & Raw Strings -> Solarized Cyan (@string #2AA198)
;; - Variables, References, Parameters, Operators & Punctuation -> Calm Base0 Grey (#839496)
;; - Comments -> Solarized Base01 Dim (@comment #586E75)

;; Comments
(comment) @comment

;; Package & Import declarations
(package) @keyword

(import) @keyword.import

;; Structural & query keywords -> Solarized Green (#859900)
[
  (default)
  (some)
  (contains)
  (with)
  (as)
] @keyword

[
  (in)
  (not)
] @keyword.operator

;; Conditional & quantifier control flow -> Solarized Yellow (#B58900)
[
  (if)
  (else)
] @keyword.conditional

(every) @keyword.repeat

;; Variables, references, and member accesses -> Calm Base0 Grey (#839496)
(var) @variable

(term
  (ref
    (var) @variable))

(ref_arg_dot
  (var) @variable.member)

(expr_every
  (var) @variable)

(rule_args
  (term) @variable.parameter)

;; Function & method calls -> Calm Base0 Grey (#839496)
(expr_call
  func_name: (fn_name
    (var) @function.call))

;; Rule & helper function declarations -> Solarized Blue (#268BD2)
(rule
  (rule_head
    (var) @function))

;; Package & import module paths / aliases -> Solarized Violet (#6C71C4)
(module
  (ref
    (var) @module))

(module
  (ref
    (ref_arg
      (ref_arg_dot
        (var) @module))))

(module
  (var) @module)

;; ALL_CAPS constants (both declaration and reference) -> Solarized Magenta (#D33682)
((var) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]*$")
  (#set! priority 110))

;; Booleans, null, and numeric literals (including unified unary sign) -> Solarized Magenta (#D33682)
[
  (boolean)
  "true"
  "false"
] @boolean

"null" @constant.builtin

(number) @number

(expr_unary
  "-" @number
  (expr
    (term
      (scalar
        (number)))))

;; Strings (quoted and raw backtick strings) -> Solarized Cyan (#2AA198)
[
  (string)
  (quoted_string)
  (raw_string)
] @string

;; Operators, brackets, and delimiters -> Calm Base0 Grey (#839496)
[
  (assignment_operator)
  (bool_operator)
  (arith_operator)
  (bin_operator)
] @operator

[
  (open_paren)
  (close_paren)
  (open_bracket)
  (close_bracket)
  (open_curly)
  (close_curly)
] @punctuation.bracket

[
  "."
  ","
  ":"
  ";"
  "|"
] @punctuation.delimiter
