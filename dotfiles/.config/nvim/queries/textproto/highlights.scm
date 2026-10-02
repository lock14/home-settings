;; Protocol Buffers Text Format (.textproto / .pbtxt) Tree-sitter Base Query
;; Supersedes upstream base queries to enforce the Universal Semantic Color Contract:
;; - Message Block Field Headers (recorded_at {, route_quotas <, metrics: [{) -> Solarized Blue (@tag #268BD2)
;; - Scalar & Array Field Keys (batch_id:, sequence_num:, quantile_bounds:) -> Solarized Green (@property.textproto #859900)
;; - Bracketed Extension & Any Type URL Identifiers ([telemetry.v1.routing_extension], [type.example.com/...]) -> Solarized Violet (@module #6C71C4)
;; - Strings & Escape Sequences -> Solarized Cyan (@string / @string.escape #2AA198)
;; - Numbers (including negative sign), Special Floats (inf, -inf, nan), Booleans & Enum Constants -> Solarized Magenta (#D33682)
;; - Structural Brackets, Delimiters & Separators -> Calm Base0 Grey (#839496)
;; - Comments -> Solarized Base01 Dim (@comment #586E75)

;; Comments
(comment) @comment

;; Macro-level message container field headers -> Solarized Blue (#268BD2)
(message_field
  (field_name
    (identifier) @tag))

;; Scalar & array property keys -> Solarized Green (#859900)
(scalar_field
  (field_name
    (identifier) @property.textproto))

;; Bracketed extension & google.protobuf.Any schema type URL identifiers -> Solarized Violet (#6C71C4)
(extension_name
  (type_name
    (identifier) @module))

(any_name
  (domain
    (identifier) @module))

(any_name
  (type_name
    (identifier) @module))

;; Strings and escape sequences -> Solarized Cyan (#2AA198)
(string) @string

(string_escape) @string.escape

;; Numbers (including leading sign), special floats, booleans, and enum constants -> Solarized Magenta (#D33682)
(number) @number

(number
  "-" @number
  (#set! priority 130))

(number
  (float) @number.float)

(scalar_value
  (signed_identifier) @number.float)

(scalar_value
  (signed_identifier
    "-" @number.float
    (identifier) @number.float)
  (#set! priority 130))

(scalar_value
  (identifier) @constant)

((scalar_value
  (identifier) @number.float)
  (#any-of? @number.float "inf" "infinity" "nan")
  (#set! priority 130))

((scalar_value
  (identifier) @boolean)
  (#any-of? @boolean "true" "false")
  (#set! priority 130))

;; Brackets, delimiters, and separators -> Calm Base0 Grey (#839496)
[
  (open_squiggly)
  (close_squiggly)
  (open_arrow)
  (close_arrow)
  (open_square)
  (close_square)
] @punctuation.bracket

[
  ":"
  ";"
  ","
  "."
  "/"
] @punctuation.delimiter

;; Shield decimal point inside float literals after generic "." delimiter rule -> Solarized Magenta (#D33682)
(float_lit
  "." @number.float
  (#set! priority 130))
