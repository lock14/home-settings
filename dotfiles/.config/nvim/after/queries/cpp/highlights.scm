;; extends
(preproc_defined "defined" @keyword)

;; Highlight custom type identifiers inside sizeof(...) as @type
(sizeof_expression
  (parenthesized_expression
    (identifier) @type
    (#match? @type "^([A-Z]|.+_t$)")))

;; Constrained concept type parameter in template: template <Printable T>
(template_parameter_list
  (parameter_declaration
    type: (type_identifier)
    declarator: (identifier) @type))

;; Variadic constrained concept parameter: template <Printable... Args>
(template_parameter_list
  (variadic_parameter_declaration
    type: (type_identifier)
    declarator: (variadic_declarator (identifier) @type)))

;; Namespace declarations: namespace core::telemetry
(namespace_definition
  name: (nested_namespace_specifier
    (namespace_identifier) @module))
(namespace_definition
  name: (namespace_identifier) @module)

;; Namespace qualifiers in code (e.g. std::string, std::move, core::telemetry::foo)
;; remain calm in neutral Base0 grey (@variable) matching Go dot qualifiers (context.Context, fmt.Sprintf).
(qualified_identifier
  scope: (namespace_identifier) @variable
  (#match? @variable "^[a-z]"))

;; Using namespace declarations: using namespace core::telemetry;
(using_declaration
  "namespace"
  (qualified_identifier
    scope: (namespace_identifier) @module
    name: (identifier) @module))
(using_declaration
  "namespace"
  (identifier) @module)

;; Scoped enum members and static class constants: NodeState::Initializing, NodeState::Active
((qualified_identifier
   scope: (namespace_identifier) @type
   name: [
     (identifier)
     (type_identifier)
   ] @constant)
 (#match? @type "^[A-Z]")
 (#match? @constant "^[A-Z]"))

;; Standard sentinel constants: std::nullopt, std::npos
((qualified_identifier
   scope: (namespace_identifier) @_scope
   name: (identifier) @constant)
 (#eq? @_scope "std")
 (#any-of? @constant "nullopt" "npos"))

;; Standard and vendor attributes: [[nodiscard]], [[maybe_unused]], etc. -> unified Violet (@attribute)
(attribute_declaration
  "[[" @attribute
  "]]" @attribute
  (#set! "priority" 105))
(attribute
  name: (identifier) @attribute
  (#set! "priority" 105))

;; Switch default branch -> Yellow (@keyword.conditional)
(case_statement
  "default" @keyword.conditional
  (#set! "priority" 105))

;; noexcept specifier is a declaration modifier (Green @keyword.modifier), not runtime control flow
("noexcept" @keyword.modifier
  (#set! "priority" 105))

;; Preprocessor #include directive -> Solarized Orange (@keyword.directive #CB4B16) matching bat and cInclude
(preproc_include
  "#include" @keyword.directive
  (#set! "priority" 105))

;; C++ static_assert declaration keyword -> Solarized Green (@keyword #859900) matching bat
(static_assert_declaration
  "static_assert" @keyword
  (#set! "priority" 105))

;; Destructor name (~ClusterNode) -> unified Solarized Blue (@function #268BD2) matching bat
(destructor_name
  "~" @function
  (#set! "priority" 105))

