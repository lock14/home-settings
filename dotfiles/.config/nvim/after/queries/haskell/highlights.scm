;; extends

; ============================================================================
; Solarized Dark Architecture: Haskell (Tier 4 Functional)
; ============================================================================

; Neutralize upstream's whole-(decl/signature) @function capture so ::, ->, =>,
; brackets, and type variables inside signatures remain in calm Base0 (#839496).
(decl/signature
  name: (variable) @function
  (#set! priority 125))

(decl/signature
  "::" @operator
  (#set! priority 120))

(decl/function
  name: (variable) @function
  (#set! priority 125))

(decl/bind
  name: (variable) @variable
  (#set! priority 115))

; Keep local let/where bindings and local helper functions in calm Base0 (#839496)
(local_binds
  (decl/bind
    name: (variable) @variable
    (#set! priority 130)))

(local_binds
  (decl/function
    name: (variable) @variable
    (#set! priority 130)))

((type/variable) @variable
  (#set! priority 115))

([
  "::"
  "->"
  "<-"
  "=>"
  "="
  "|"
  "."
  ".."
] @operator
  (#set! priority 120))

((operator) @operator
  (#set! priority 120))

([
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket
  (#set! priority 120))

([
  ","
  ";"
] @punctuation.delimiter
  (#set! priority 120))

; Pragmas {-# LANGUAGE ... #-} in Solarized Orange (#CB4B16)
((pragma) @keyword.directive
  (#set! priority 120))

; Formal module header and import declarations in Solarized Violet (#6C71C4),
; while in-code qualified module prefixes (Map.lookup, Map.Map) remain in calm Base0 (#839496).
([
  "module"
  "import"
  "qualified"
] @keyword.import
  (#set! priority 120))

(header
  (module) @module
  (#set! priority 125))

(import
  module: (module) @module
  (#set! priority 125))

(import
  alias: (module) @module
  (#set! priority 125))

(qualified
  module: (module) @type
  (#set! priority 120))

; Record field declarations and usages in calm Base0 (#839496)
(field_name
  (variable) @variable.member
  (#set! priority 120))

; Neutralize upstream's @function capture on function composition operands (f . g)
; and routine calls so invocations remain in calm Base0 (#839496).
(apply
  function: (variable) @function.call
  (#set! priority 115))

(apply
  function: (qualified
    (variable) @function.call)
  (#set! priority 120))

((expression/variable) @variable
  (#set! priority 115))

(expression/qualified
  (variable) @function.call
  (#set! priority 120))

; Scalar primitive types in Solarized Green (#859900)
((name) @type.builtin
  (#any-of? @type.builtin
    "Int" "Int8" "Int16" "Int32" "Int64" "Integer"
    "Word" "Word8" "Word16" "Word32" "Word64"
    "Float" "Double" "Bool" "Char" "String")
  (#set! priority 120))

; Booleans, otherwise, and Nothing sentinel in Solarized Magenta (#D33682)
((constructor) @boolean
  (#any-of? @boolean "True" "False")
  (#set! priority 120))

((constructor) @constant.builtin
  (#eq? @constant.builtin "Nothing")
  (#set! priority 120))

((variable) @boolean
  (#eq? @boolean "otherwise")
  (#set! priority 120))

; Structural keywords (including forall, as, hiding, where) in Solarized Green (#859900)
([
  "data"
  "newtype"
  "type"
  "class"
  "instance"
  "deriving"
  "where"
  "let"
  "in"
  "forall"
  "∀"
  "as"
  "hiding"
  "family"
  "role"
  "pattern"
  "default"
  "infix"
  "infixl"
  "infixr"
] @keyword
  (#set! priority 120))

; Control flow keywords (including do / mdo) in Solarized Yellow (#B58900)
([
  "if"
  "then"
  "else"
  "case"
  "of"
  "do"
  "mdo"
] @keyword.conditional
  (#set! priority 120))
