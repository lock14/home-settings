;; Lean 4 Tree-sitter Highlights — Solarized Dark Universal Semantic Color Contract
;; Base query (no `;; extends`) for Julian/tree-sitter-lean

;; ---------------------------------------------------------------------------
;; 1. Monotone Canvas Ground (Solarized Base0 #839496)
;;    Generic catch-all patterns precede specialized predicate rules.
;; ---------------------------------------------------------------------------
(identifier) @variable

(proj field: (identifier) @property)
(field name: (identifier) @property)
(struct_field name: (identifier) @property)
(ctor name: (identifier) @constructor)
(ctor_alt name: (identifier) @constructor)
(dot_ident name: (identifier) @property)

(app fn: (identifier) @function.call)
(app fn: (proj field: (identifier) @function.call))

[
  "("
  ")"
  "["
  "]"
  "#["
  "{"
  "}"
  "⦃"
  "⦄"
  "{{"
  "}}"
  "⟨"
  "⟩"
  "‹"
  "›"
  "⟦"
  "⟧"
  "⟪"
  "⟫"
  "⌊"
  "⌋"
  "⌋₊"
  "⌈"
  "⌉"
  "⌉₊"
] @punctuation.bracket

[
  ","
  ";"
  "."
  "|"
] @punctuation.delimiter

[
  "→" "->" "↔" "<->" "↦" "=>"
  "∨" "||" "∧" "&&" "¬" "!"
  "=" "==" "≠" "!=" "<" "≤" "<=" ">" "≥" ">="
  "∈" "∉" "⊆" "⊂" "⊇" "⊃"
  "≡" "≢" "~" "≃" "≅"
  "::" "++"
  "+" "-" "*" "/" "%"
  "∪" "∩" "\\"
  "^" "∘"
  "|>" "<|"
  ">>" "<<" ">>>" "<<<"
  ">>=" "=<<"
  "<$>" "<*>" "<|>" "<&>"
  "&&&" "|||" "^^^"
  "←" "<-"
  ":=" ":"
] @operator

;; ---------------------------------------------------------------------------
;; 2. Comments & Documentation (Solarized Base01 #586E75 Italic)
;; ---------------------------------------------------------------------------
[
  (line_comment)
  (block_comment)
  (doc_comment)
  (module_doc_comment)
] @comment

;; ---------------------------------------------------------------------------
;; 3. Compiler Directives & Interactive Commands (Solarized Orange #CB4B16)
;; ---------------------------------------------------------------------------
[
  "#check"
  "#eval"
  "#print"
  "#reduce"
] @keyword.directive

;; ---------------------------------------------------------------------------
;; 4. Module Imports, Namespaces & Unified Attributes (Solarized Violet #6C71C4)
;; ---------------------------------------------------------------------------
[
  "import"
  (moduleTk)
  (prelude)
] @keyword.import

(import name: (identifier) @module (#set! "priority" 125))
(namespace name: (identifier) @module (#set! "priority" 125))
(section name: (identifier) @module (#set! "priority" 125))
(end name: (identifier) @module (#set! "priority" 125))
(open namespace: (identifier) @module (#set! "priority" 125))
(open scoped: (identifier) @module (#set! "priority" 125))
(export namespace: (identifier) @module (#set! "priority" 125))

;; Unified atomic attributes (@[simp], @[inline], @[deriving Repr, BEq, Inhabited])
(attributes) @attribute
(attributes
  ["@[" "]" ","] @attribute
  (#set! "priority" 130))
(attributes
  (identifier) @attribute
  (#set! "priority" 130))

;; ---------------------------------------------------------------------------
;; 5. Structural Scaffolding, Modifiers & Scalar Primitives (Solarized Green #859900)
;; ---------------------------------------------------------------------------
[
  "namespace"
  "section"
  "end"
  "def"
  "theorem"
  "example"
  "abbrev"
  "instance"
  "axiom"
  "opaque"
  "constant"
  "structure"
  "inductive"
  "class"
  "where"
  "deriving"
  "extends"
  "variable"
  "universe"
  "universes"
  "open"
  "export"
  "fun"
  "λ"
  "let"
  "have"
  "show"
  "from"
  "by"
  "forall"
  "∀"
  "Π"
  "exists"
  "∃"
  "Σ"
  "Σ'"
] @keyword

((identifier) @keyword
  (#any-of? @keyword
    "mutual" "lemma" "letI" "haveI" "obtain" "set" "suffices"
    "macro" "macro_rules" "syntax" "elab_rules" "notation"
    "infix" "infixl" "infixr" "prefix" "postfix" "alias"
    "initialize" "builtin_initialize" "set_option")
  (#set! "priority" 125))

[
  "noncomputable"
  "partial"
  "nonrec"
  "private"
  "protected"
  "unsafe"
  "scoped"
  "local"
  (public)
  (meta)
  "mut"
] @keyword.modifier

((identifier) @keyword.modifier
  (#any-of? @keyword.modifier "rec" "nomatch")
  (#set! "priority" 125))

(type_const "Type" @type.builtin)
(sort_const "Sort" @type.builtin)
(prop_const) @type.builtin

((identifier) @type.builtin
  (#any-of? @type.builtin
    "Nat" "Int" "UInt8" "UInt16" "UInt32" "UInt64" "USize"
    "Int8" "Int16" "Int32" "Int64" "ISize"
    "Float" "Float32" "Bool" "Char" "String" "Unit" "Empty" "PUnit" "PEmpty" "ByteArray")
  (#set! "priority" 125))

;; ---------------------------------------------------------------------------
;; 6. Control Flow & Execution Jumps (Solarized Yellow #B58900)
;; ---------------------------------------------------------------------------
(if_then_else ["if" "then" "else"] @keyword.conditional)
(match ["match" "with"] @keyword.conditional)
(induction ["induction" "cases" "with"] @keyword.conditional)
(tactic_case "case" @keyword.conditional)
(do_block "do" @keyword.repeat)
(sorry) @keyword.exception

((identifier) @keyword.return
  (#any-of? @keyword.return "return")
  (#set! "priority" 125))

((identifier) @keyword.repeat
  (#any-of? @keyword.repeat "for" "while" "repeat" "break" "continue")
  (#set! "priority" 125))

((identifier) @keyword.conditional
  (#any-of? @keyword.conditional "unless" "by_cases")
  (#set! "priority" 125))

((identifier) @keyword.exception
  (#any-of? @keyword.exception "try" "catch" "finally" "throw")
  (#set! "priority" 125))

;; ---------------------------------------------------------------------------
;; 7. Routine & Theorem Declarations (Solarized Blue #268BD2)
;; ---------------------------------------------------------------------------
(def name: (identifier) @function (#set! "priority" 120))
(theorem name: (identifier) @function (#set! "priority" 120))
(abbrev name: (identifier) @function (#set! "priority" 120))
(opaque name: (identifier) @function (#set! "priority" 120))
(constant name: (identifier) @function (#set! "priority" 120))
(axiom name: (identifier) @function (#set! "priority" 120))
(instance name: (identifier) @function (#set! "priority" 120))
(where_aux_def name: (identifier) @function (#set! "priority" 120))

;; ---------------------------------------------------------------------------
;; 8. Constants, Numbers, Booleans, Holes & Quoted Names (Solarized Magenta #D33682)
;; ---------------------------------------------------------------------------
(num_lit) @number
(scientific_lit) @number.float

[
  (true_const)
  (false_const)
] @boolean

[
  (bot_const)
  (top_const)
  (empty_const)
  (goal_const)
] @constant.builtin

[
  (hole)
  (synth_hole)
] @variable.builtin

(named_hole
  "?" @variable.builtin
  (identifier) @variable.builtin
  (#set! "priority" 130))

(name_lit) @constant
(name_lit ["`" "``"] @constant (#set! "priority" 130))
(name_lit name: (identifier) @constant (#set! "priority" 130))

((identifier) @constant.builtin
  (#any-of? @constant.builtin "none")
  (#set! "priority" 125))

((identifier) @constant
  (#lua-match? @constant "^[A-Z][A-Z0-9_]+$")
  (#set! "priority" 125))

;; ---------------------------------------------------------------------------
;; 9. Strings, Characters, Interpolated Strings & Escapes (Solarized Cyan #2AA198)
;; ---------------------------------------------------------------------------
[
  (str_lit)
  (raw_string)
  (interpolated_str)
] @string

(char_lit) @character
(escape_sequence) @string.escape

(interpolation
  "{" @punctuation.special
  "}" @punctuation.special
  (#set! "priority" 130))

(interpolation
  (identifier) @variable
  (#set! "priority" 120))
