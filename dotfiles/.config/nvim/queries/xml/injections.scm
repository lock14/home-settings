;; Overrides upstream tree-sitter-xml injections
;; Prevents blind JavaScript injection into arbitrary XML <script> tags (such as shell scripts or CDATA)

((Comment) @injection.content
  (#set! injection.language "comment"))

; SVG style
((element
  (STag
    (Name) @_name)
  (content) @injection.content)
  (#eq? @_name "style")
  (#set! injection.combined)
  (#set! injection.include-children)
  (#set! injection.language "css"))

; Explicit JavaScript / ECMAScript scripts
((element
  (STag
    (Name) @_name
    (Attribute
      (Name) @_attr_name
      (AttValue) @_attr_val))
  (content) @injection.content)
  (#eq? @_name "script")
  (#eq? @_attr_name "type")
  (#match? @_attr_val "javascript|ecmascript")
  (#set! injection.combined)
  (#set! injection.include-children)
  (#set! injection.language "javascript"))

; phpMyAdmin dump
((element
  (STag
    (Name) @_name)
  (content) @injection.content)
  (#eq? @_name "pma:table")
  (#set! injection.combined)
  (#set! injection.include-children)
  (#set! injection.language "sql"))
