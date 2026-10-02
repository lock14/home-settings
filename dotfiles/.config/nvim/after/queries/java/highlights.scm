;; extends

; Map import keyword to @keyword.import linking to Include (Solarized Violet #6c71c4)
(import_declaration "import" @keyword.import)

; Package path segments in import declarations remain in calm Base0 Grey (@variable #839496)
(import_declaration
  (scoped_identifier
    scope: (scoped_identifier) @variable))
(import_declaration
  (scoped_identifier
    scope: (identifier) @variable))
(import_declaration
  (scoped_identifier
    scope: (scoped_identifier
      scope: (identifier) @variable
      name: (identifier) @variable)))
(import_declaration
  (scoped_identifier
    scope: (scoped_identifier
      scope: (scoped_identifier
        scope: (identifier) @variable
        name: (identifier) @variable)
      name: (identifier) @variable)))
(import_declaration
  (scoped_identifier
    scope: (scoped_identifier
      scope: (scoped_identifier
        scope: (scoped_identifier
          scope: (identifier) @variable
          name: (identifier) @variable)
        name: (identifier) @variable)
      name: (identifier) @variable)))

; Map package keyword to @keyword (Solarized Green #859900)
(package_declaration "package" @keyword)

; Model 2: Package declaration identifiers are Solarized Violet (@module #6c71c4)
(package_declaration
  (scoped_identifier) @module)
(package_declaration
  (identifier) @module)
(package_declaration
  (scoped_identifier
    scope: (identifier) @module
    name: (identifier) @module))
(package_declaration
  (scoped_identifier
    scope: (scoped_identifier
      scope: (identifier) @module
      name: (identifier) @module)
    name: (identifier) @module))
(package_declaration
  (scoped_identifier
    scope: (scoped_identifier
      scope: (scoped_identifier
        scope: (identifier) @module
        name: (identifier) @module)
      name: (identifier) @module)
    name: (identifier) @module))
(package_declaration
  (scoped_identifier
    scope: (scoped_identifier
      scope: (scoped_identifier
        scope: (scoped_identifier
          scope: (identifier) @module
          name: (identifier) @module)
        name: (identifier) @module)
      name: (identifier) @module)
    name: (identifier) @module))

; Record declaration keyword is @keyword.type (Solarized Green #859900)
(record_declaration "record" @keyword.type)

; Java 21 Record Pattern type identifier in switch cases: case OrderRecord(...) -> @type (Base0 #839496)
(record_pattern
  (identifier) @type)

; Java 21 Pattern Matching guard keyword: when -> @keyword.conditional (Solarized Yellow #b58900)
(guard "when" @keyword.conditional)

; Annotation type declaration keyword: @interface -> @attribute (Solarized Violet #6C71C4)
(annotation_type_declaration "@interface" @attribute)

; Disambiguate switch default branch: case null, default -> ... -> @keyword.conditional
(switch_label "default" @keyword.conditional)
(switch_label
  (identifier) @keyword.conditional
  (#eq? @keyword.conditional "default"))

; Annotation type element declaration name: String value() default ""; -> @function.method (Blue #268BD2)
(annotation_type_element_declaration
  name: (identifier) @function.method)

; Java 22+ unnamed variables and patterns (_) -> calm Base0 Grey (@variable #839496)
((underscore_pattern) @variable
  (#set! "priority" 105))



