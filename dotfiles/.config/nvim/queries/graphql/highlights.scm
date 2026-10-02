;; GraphQL Schema & Query Language Tree-sitter Base Query
;; Supersedes upstream base queries to enforce the Universal Semantic Color Contract:
;; - Structural & Declarative Keywords (schema, scalar, type, interface, union, enum, input, extend,
;;   implements, directive, repeatable, on, query, mutation, subscription, fragment) -> Solarized Green (#859900)
;; - Built-in Scalar Types (Int, Float, String, Boolean, ID) -> Solarized Green (@type.builtin #859900)
;; - User-Defined Types (Scalars, Objects, Interfaces, Unions, Enums, Inputs) -> Calm Base0 Grey (@type #839496)
;; - Field Definitions, Input Fields, Selection Fields, Aliases & Object Keys -> Solarized Green (@property #859900)
;; - Operation & Fragment Declarations (query Get..., fragment Node...) -> Solarized Blue (@function #268BD2)
;; - Directives (@deprecated, @rateLimit, @specifiedBy, @auth) -> Solarized Violet (@attribute #6C71C4)
;; - Enum Values, Directive Locations, Numbers, Booleans & null -> Solarized Magenta (#D33682)
;; - Strings & Block Strings ("""...""") -> Solarized Cyan (@string #2AA198)
;; - Arguments, Variables ($var), Fragment Spreads, Operators & Delimiters -> Calm Base0 Grey (#839496)
;; - Comments (# ...) -> Solarized Base01 Dim (@comment #586E75)
;; - Zero Yellow (#B58900) in declarative schema & query documents.

;; Comments
(comment) @comment

;; Structural & declarative keywords -> Solarized Green (#859900)
[
  "schema"
  "scalar"
  "input"
  "extend"
  "directive"
  "on"
  "repeatable"
  "implements"
  "query"
  "mutation"
  "subscription"
  "fragment"
] @keyword

[
  "enum"
  "union"
  "type"
  "interface"
] @keyword.type

;; User-defined types -> Calm Base0 Grey (#839496)
(scalar_type_definition
  (name) @type)

(object_type_definition
  (name) @type)

(interface_type_definition
  (name) @type)

(union_type_definition
  (name) @type)

(enum_type_definition
  (name) @type)

(input_object_type_definition
  (name) @type)

(scalar_type_extension
  (name) @type)

(object_type_extension
  (name) @type)

(interface_type_extension
  (name) @type)

(union_type_extension
  (name) @type)

(enum_type_extension
  (name) @type)

(input_object_type_extension
  (name) @type)

(named_type
  (name) @type)

;; Built-in scalar types -> Solarized Green (#859900)
((named_type
  (name) @type.builtin)
  (#any-of? @type.builtin "Int" "Float" "String" "Boolean" "ID")
  (#set! priority 110))

;; Operation & fragment declarations -> Solarized Blue (#268BD2)
(operation_definition
  (name) @function)

(fragment_definition
  (fragment_name
    (name) @function))

;; Fragment spread references -> Calm Base0 Grey (#839496)
(fragment_spread
  (fragment_name
    (name) @variable))

;; Directives -> Solarized Violet (#6C71C4)
(directive_definition
  "@" @attribute
  (name) @attribute)

(directive
  "@" @attribute
  (name) @attribute)

;; Field definitions, input fields, selection set fields, aliases & object keys -> Solarized Green (#859900)
(field
  (name) @property)

(field
  (alias
    (name) @property))

(field_definition
  (name) @property)

(input_fields_definition
  (input_value_definition
    (name) @property))

(object_value
  (object_field
    (name) @property))

;; Arguments & variables -> Calm Base0 Grey (#839496)
(argument
  (name) @variable.parameter)

(arguments_definition
  (input_value_definition
    (name) @variable.parameter))

(variable
  "$" @punctuation.special
  (name) @variable)

;; Enum values, directive locations, booleans, null & numbers -> Solarized Magenta (#D33682)
(enum_value
  (name) @constant)

(directive_location
  (executable_directive_location) @constant.builtin)

(directive_location
  (type_system_directive_location) @constant.builtin)

(boolean_value) @boolean

(null_value) @constant.builtin

(int_value) @number

(float_value) @number.float

;; Strings & block strings -> Solarized Cyan (#2AA198)
(string_value) @string

(description
  (string_value) @string)

;; Punctuation & operators -> Calm Base0 Grey (#839496)
[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

"=" @operator

(comma) @punctuation.delimiter

[
  "|"
  "&"
  ":"
] @punctuation.delimiter

[
  "..."
  "!"
] @punctuation.special
