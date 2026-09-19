; inherits: html_tags

;; Solarized Dark TrueColor Tree-sitter Base Query for HTML Documents
;; Complies with Principle I (Base Query Supersedure without ';; extends')
;; - Doctype (<!DOCTYPE html>): Solarized Orange (@keyword.directive)
;; - Entity References (&copy;, &mdash;, &amp;): Solarized Magenta (@constant.builtin)
;; - Inherits html_tags base query for tags, delimiters, attributes, and calm Base0 text

(doctype) @keyword.directive

"<!" @tag.delimiter

(entity) @constant.builtin
