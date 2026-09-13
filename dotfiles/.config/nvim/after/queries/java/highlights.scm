;; extends

; Map import keyword to @keyword.import linking to Include (Solarized Orange #cb4b16)
(import_declaration "import" @keyword.import)

; Map package keyword to @keyword (Solarized Green #859900)
(package_declaration "package" @keyword)

; Model 2: Package declaration identifier is Solarized Violet (@module #6c71c4)
(package_declaration
  (scoped_identifier) @module)
(package_declaration
  (identifier) @module)

; Record declaration keyword is @keyword.type (Solarized Green #859900)
(record_declaration "record" @keyword.type)

; Java 21 Record Pattern type identifier in switch cases: case OrderRecord(...) -> @type (Yellow #b58900)
(record_pattern
  (identifier) @type)

; Java 21 Pattern Matching guard keyword: when -> @keyword.conditional (Solarized Green #859900)
(guard "when" @keyword.conditional)
