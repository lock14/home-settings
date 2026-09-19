;; Solarized Dark TrueColor Tree-sitter Base Query for HTML Tags
;; Complies with Principle I (Base Query Supersedure without ';; extends')
;; - Prevents rogue OSC 8 terminal hyperlinks by omitting upstream 'url' extmark metadata
;; - Upholds Principle II (Canvas Tranquility): document prose in calm Base0 Grey (@markup.raw.block)
;; - Upholds Principle III: pure monospace typography without artificial bolding or italics
;; - Tags in Solarized Blue (@tag), delimiters & attributes in Base0 Grey, attribute values in Cyan

(tag_name) @tag @nospell

(comment) @comment @spell

(attribute_name) @tag.attribute @nospell

(attribute_value) @nospell

((attribute
  (quoted_attribute_value) @string)
  (#set! priority 99))

(text) @markup.raw.block

[
  "<"
  ">"
  "</"
  "/>"
] @tag.delimiter

"=" @operator
