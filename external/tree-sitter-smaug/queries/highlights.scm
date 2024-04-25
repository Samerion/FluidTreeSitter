; Tokens
[
    "module"
    "import"
    "let"
    "struct"
    "enum"
    "union"
    "class"
    "external"
] @keyword
[
    "do"
    "if"
    "else"
    "each"
    "match"
    "case"
    "return"
] @keyword.control
("case" "default" @keyword.control)
(yield "yield" @keyword.control)
(yield_attribute "yield" @attribute)
(built_in) @type.builtin
[
    "+"
    "-"
    "!"
    "*"
    "/"
    "%"
    "<"
    "<="
    "=="
    "!="
    ">="
    ">"
    "="
    "..."
    "in"
] @operator
[
    "."
    ","
    ":"
] @punctuation.delimiter
[
    "("
    ")"
    "["
    "]"
    "{"
    "}"
] @punctuation.bracket
(comment) @comment

; Literals
(integer) @number
(string) @string

; Unknown identifier
(qualified_identifier (identifier) @constant
 (#is-not? local))

; Patterns
(identifier_pattern
  name: (identifier) @constant)
(enum_pattern name: (identifier) @type.struct)

; Assumptions
; In some cases we can assume an identifier expression is of a certain type.
; Each type assumption has two versions, one that matches direct qualified identifiers, and one that matches identifiers
; at the righthand side of a member expression.
(identifier_pattern
  type: (qualified_identifier (identifier) @type .))
(identifier_pattern
  type: (member_expression
    rhs: (qualified_identifier (identifier) @type .)))
(function_signature_pattern
  type: (qualified_identifier (identifier) @type .))
(function_signature_pattern
  type: (member_expression
    rhs: (qualified_identifier (identifier) @type .)))
(yield_attribute
  type: (qualified_identifier (identifier) @type .))
(yield_attribute
  type: (member_expression
    rhs: (qualified_identifier (identifier) @type .)))

; Function assumptions come in three versions: one for regular functions (member access implies a method) and two for
; methods
(each
  pattern: (let_variable
    value: (qualified_identifier . (identifier) @function .)))
(each
  pattern: (let_variable
    value: (qualified_identifier (identifier) (identifier) @function.method .)))
(each
  pattern: (let_variable
    value: (member_expression
      rhs: (qualified_identifier (identifier) @function.method .))))

; Declarations
(let_function name: (identifier) @function)
(let_enum name: (identifier) @type.enum)

; Expressions
(call_expression
  callee: (qualified_identifier . (identifier) @function .))
(call_expression
  callee: (member_expression
    rhs: (qualified_identifier (identifier) @function.method .)))
(call_expression
  callee: (qualified_identifier (identifier) (identifier) @function.method .))
(binary_expression
  ":" @operator)

; Statements
(module name: (qualified_identifier ((identifier) "."?)+ @module) @module)
(import module: (qualified_identifier ((identifier) "."?)+ @module) @module)
