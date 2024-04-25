; Uses Samerion Studio @indent conventions, which are partially compatible with neovim's

["{" "(" "/*"] @indent.begin
["}" ")" "*/"] @indent.end

; Statements indent their contents
(module (_) @indent.whole)
(import (_) @indent.whole)
(do     (_) @indent.whole)
(yield  (_) @indent.whole)
(return (_) @indent.whole)
(each   (_) @indent.whole)
(if     (_) @indent.whole)
(if_let "if" @indent.begin)
(if_let then: (_) @indent.whole)
(if_let then: (_) @indent.end)
(if_let else: (_) @indent.whole)
(each_range "each" @indent.begin)
(each_range ")" @indent.end)
(each_range then: (_) @indent.whole)
(match expression: (_) @indent.whole)
(case "case" @indent.begin)
(case value: (_) @indent.end @indent.whole)
(retry_case ["case" (_)] @indent.whole)

; Let
; Indent all after the name, do it separately so that brackets are excluded
(let_variable ["=" (_)] @indent.whole)
(function_scope ["=" (_)] @indent.whole)

; Exclude content in brackets from @indent.whole indentation
(block_expression) @indent.exclude
