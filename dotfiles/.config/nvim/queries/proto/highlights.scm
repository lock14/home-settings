;; Protocol Buffers (proto2 / proto3 / editions) Tree-sitter Base Query
;; Supersedes upstream base queries to enforce the Universal Semantic Color Contract:
;; - Grammar Directives (syntax, edition) -> Solarized Orange (@keyword.directive #CB4B16)
;; - Module Import Keyword (import) -> Solarized Violet (@keyword.import #6C71C4)
;; - Package Keyword (package) -> Solarized Green (@keyword #859900)
;; - Formal Package Declaration Identifiers (package telemetry.v1;) -> Solarized Violet (@module #6C71C4)
;; - Structural & Declarative Keywords (message, enum, oneof, service, rpc, returns, option, extend,
;;   extensions, reserved, to, max, map, repeated, optional, required, stream, public, weak) -> Solarized Green (#859900)
;; - Built-in Scalar Types -> Solarized Green (@type.builtin #859900)
;; - User-Defined Message, Enum & Service Types -> Calm Base0 Grey (@type #839496)
;; - RPC Method Declarations (rpc IngestBatch) -> Solarized Blue (@function.method #268BD2)
;; - Field, Oneof & Option Identifiers -> Calm Base0 Grey (@variable.member / @property #839496)
;; - Enum Variants, Tag Numbers, Numeric Literals (including sign) & Booleans -> Solarized Magenta (#D33682)
;; - Strings & Escape Sequences -> Solarized Cyan (@string / @string.escape #2AA198)
;; - Operators, Brackets & Delimiters -> Calm Base0 Grey (#839496)
;; - Comments -> Solarized Base01 Dim (@comment #586E75)

;; Comments
(comment) @comment

;; Top-of-file schema grammar directives
[
  "syntax"
  "edition"
] @keyword.directive

;; Module import keyword
"import" @keyword.import

;; Package declaration
"package" @keyword

(package
  (full_ident
    (identifier) @module))

;; Structural & declarative keywords (note: "returns" is a declarative signature keyword in Green, never Yellow)
[
  "option"
  "extensions"
  "reserved"
  "to"
  "max"
  "map"
  "returns"
] @keyword

[
  "enum"
  "message"
  "service"
  "oneof"
  "extend"
] @keyword.type

"rpc" @keyword.function

[
  "optional"
  "repeated"
  "required"
  "stream"
  "public"
  "weak"
] @keyword.modifier

;; Built-in scalar types -> Solarized Green (#859900)
(key_type) @type.builtin

(type
  [
    "double"
    "float"
    "int32"
    "int64"
    "uint32"
    "uint64"
    "sint32"
    "sint64"
    "fixed32"
    "fixed64"
    "sfixed32"
    "sfixed64"
    "bool"
    "string"
    "bytes"
  ] @type.builtin)

;; User-defined message, enum, and service types -> Calm Base0 Grey (#839496)
[
  (message_name)
  (enum_name)
  (service_name)
  (message_or_enum_type)
] @type

(extend
  (full_ident) @type)

;; RPC method declarations -> Solarized Blue (#268BD2)
(rpc_name
  (identifier) @function.method)

;; Field, oneof, and option identifiers -> Calm Base0 Grey (#839496)
(field
  (identifier) @variable.member)

(oneof
  (identifier) @variable.member)

(oneof_field
  (identifier) @variable.member)

(map_field
  (identifier) @variable.member)

(option
  (identifier) @variable.member)

(option
  (full_ident) @variable.member)

(field_option
  (identifier) @variable.member)

(field_option
  (full_ident) @variable.member)

(enum_value_option
  (identifier) @variable.member)

(enum_value_option
  (full_ident) @variable.member)

(block_lit
  (identifier) @property)

;; Constants, enum variants, numbers (with unified sign), and booleans -> Solarized Magenta (#D33682)
(enum_field
  (identifier) @constant)

(constant
  (full_ident) @constant)

[
  (true)
  (false)
] @boolean

(int_lit) @number

(float_lit) @number.float

(constant
  [
    "-"
    "+"
  ] @number)

(enum_field
  "-" @number)

;; Strings, syntax version literals, reserved field names, and escapes -> Solarized Cyan (#2AA198)
[
  (string)
  "\"proto3\""
  "\"proto2\""
] @string

(reserved_identifier) @string

(escape_sequence) @string.escape

;; Operators, brackets, and delimiters -> Calm Base0 Grey (#839496)
"=" @operator

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
  "<"
  ">"
] @punctuation.bracket

[
  ";"
  ","
  "."
  ":"
] @punctuation.delimiter
