;; extends

;; Solarized Dark TrueColor Tree-sitter Query Overrides for XML
;; Complies with Universal Semantic Color Contract:
;; - Directives / Processing Instructions: Solarized Orange (@keyword.directive)
;; - Element Tag Names: Solarized Blue (@tag)
;; - Tag Delimiters (<, >, </, />, <?, ?>): calm Base0 Grey (@tag.delimiter)
;; - Attribute Names: calm Base0 Grey (@tag.attribute)
;; - Attribute String Values: Solarized Cyan (@string)
;; - Builtin Entity References (&amp;, etc.): Solarized Magenta (@constant.builtin)
;; - CDATA Section Delimiters (<![CDATA[ and ]]>): Solarized Violet (@module)
;; - CDATA Payload: calm Base0 Grey (@markup.raw.block)
;; - Comments: Base01 Dim (@comment)

;; Processing instructions & XML declarations
(XMLDecl
  "xml" @keyword.directive)

(StyleSheetPI
  "xml-stylesheet" @keyword.directive)

;; In XML declaration, attribute values are strings (Solarized Cyan)
(XMLDecl
  (VersionNum) @string)

(XMLDecl
  (EncName) @string)

;; CDATA section: Violet delimiters, calm Base0 payload
;; - Upstream site query captures (CData) @markup.raw (which renders Cyan).
;; - Using @none fails because Neovim cascades attributes when fg is nil.
;; - Capturing (CData) @markup.raw.block (#set! priority 125) natively resolves
;;   to Base0 Grey (#839496) and defeats the inline code Cyan cascade.
;; - Trailing bracket '[' in '<![CDATA[' is explicitly captured with priority 130
;;   to prevent anonymous bracket leaf tokens from fracturing the delimiter.
(CDSect
  (CDStart) @module (#set! priority 125)
  (CData) @markup.raw.block (#set! priority 125)
  "]]>" @module (#set! priority 125))

(CDStart
  "[" @module (#set! priority 130))

;; Delimiters & punctuation in calm Base0 Grey
[
  "<?"
  "?>"
  "<"
  ">"
  "</"
  "/>"
] @tag.delimiter

;; Built-in entities in Solarized Magenta
((EntityRef) @constant.builtin
  (#any-of? @constant.builtin "&amp;" "&lt;" "&gt;" "&quot;" "&apos;"))
