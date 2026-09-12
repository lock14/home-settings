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

;; Using namespace declarations: using namespace core::telemetry;
(using_declaration
  "namespace"
  (qualified_identifier
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

