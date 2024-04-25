; Scopes
(source_file) @local.scope
(function_scope) @local.scope
(block_expression) @local.scope
(if) @local.scope
(each) @local.scope
(match) @local.scope

; Definitions
(identifier_pattern
  name: (identifier) @local.definition)
(let_function
  name: (identifier) @local.definition)
(let_struct
  (enum_pattern
    name: (identifier) @local.definition))
(let_enum
  name: (identifier) @local.definition)
(case
  pattern: (enum_pattern
    name: (identifier) @local.definition))

; References
(qualified_identifier . (identifier) @local.reference)
