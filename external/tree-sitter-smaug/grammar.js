function unaryOp($, op) {

    return seq(
        field("operator", op),
        field("rhs", $._expression),
    );

}

function binaryOpLeft($, precedence, op) {

    return prec.left(precedence,
        seq(
            field("lhs", $._expression),
            field("operator", op),
            field("rhs", $._expression),
        )
    );

}

module.exports = grammar({
    name: 'smaug',
    extras: $ => [
        $.comment,
        $._whitespace,
    ],
    word: $ => $._word,
    precedences: _$ => [
        [
            "member",
            "postfix",
            "unary",
            "power",
            "multiply",
            "add",
            "shift",
            "append",
            "range",
            "compare",
            "bitwise_and",
            "exclusive_or",
            "inclusive_or",
            "logical_or",
            "logical_and",
        ],
    ],
    rules: {
        source_file: $ =>
            seq(
                optional($.module),
                repeat($._statement),
            ),
        module: $ =>
            seq(
                "module",
                field("name", $.qualified_identifier),
            ),

        //
        //  Expressions
        //
        _expression: $ =>
            choice(
                $.unary_expression,
                $.binary_expression,
                $._primary_expression,
                $.member_expression,
                $.call_expression,
                $.index_expression,
                $.block_expression,
                $._statement,
                // TODO lambda
            ),
        _primary_expression: $ =>
            choice(
                $.qualified_identifier,
                $._literal,
                $.paren_expression,
                $.tuple,
                $.array,
            ),
        member_expression: $ =>
            prec("member",
                seq(
                    field("lhs", $._expression),
                    ".",
                    field("rhs", $.qualified_identifier),
                )
            ),
        paren_expression: $ =>
            prec(2,
                seq(
                    "(",
                    $._expression,
                    ")",
                ),
            ),
        unary_expression: $ =>
            choice(
                prec.left("unary", unaryOp($, "-")),
                prec.left("unary", unaryOp($, "+")),
                prec.left("unary", unaryOp($, "!")),
            ),
        binary_expression: $ =>
            choice(
                binaryOpLeft($, "multiply", choice("*", "/", "%")),
                binaryOpLeft($, "add", choice("+", "-")),
                binaryOpLeft($, "append", choice("~")),
                binaryOpLeft($, "range", choice("..")),
                binaryOpLeft($, "compare", choice("<", "<=", "==", "!=", ">=", ">", ":", "in")),
                binaryOpLeft($, "logical_or", choice("||")),
                binaryOpLeft($, "logical_and", choice("&&")),
            ),
        call_expression: $ =>
            prec("postfix",
                seq(
                    field("callee", $._expression),
                    field("arguments", $.tuple)
                ),
            ),
        index_expression: $ =>
            prec("postfix",
                seq(
                    field("array", $._expression),
                    field("indices", $.array)
                ),
            ),
        tuple: $ =>
            seq(
                "(",
                repeat(seq($._expression, ",")),
                optional($._expression),
                ")",
            ),
        array: $ =>
            seq(
                "[",
                repeat(seq($._expression, ",")),
                optional($._expression),
                "]",
            ),
        qualified_identifier: $ =>
            prec.right(
                seq(
                    $.identifier,
                    repeat(
                        seq(
                            ".",
                            $.identifier,
                        )
                    )
                ),
            ),
        // TODO test unicode support
        identifier: $ => choice($.built_in, $._word),
        _word: $ => /[_\p{L}][_\p{L}0-9]*/,
        built_in: $ => choice(
            "byte",
            "int",
            "long",
            "float",
            "char",
            "wchar",
            "dchar",
        ),
        reserved: $ =>
            choice(
                "import",
                "let",
                "struct",
                "enum",
                "union",
                "class",
                "do",
                "yield",
                "return",
                "if",
                "in",
                "each",
                "match",
                "case",
                "external",
            ),
        block_expression: $ =>
            seq(
                "{",
                repeat($._statement),
                "}",
            ),

        //
        //  Patterns
        //
        function_signature_pattern: $ =>
            prec.left(2,
                seq(
                    field("arguments", $.tuple_pattern),
                    optional(
                        seq(
                            ":",
                            field("type", $._expression),
                        )
                    ),
                    optional(
                        field("attributes", $._function_attributes),
                    ),
                ),
            ),
        _function_attributes: $ =>
            seq(
                repeat(
                    seq(
                        $.yield_attribute,
                        ",",
                    ),
                ),
                $.yield_attribute,
                optional(",")
            ),
        yield_attribute: $ =>
            prec.left(
                1,
                seq(
                    "yield",
                    field("type", $._expression)
                ),
            ),
        _value_pattern: $ => choice(
            $.construct_pattern,
            $.identifier_pattern,
            $.tuple_pattern,
            $.enum_pattern,
            $.literal_pattern,
        ),
        construct_pattern: $ =>
            seq(
                "...",
                $.identifier_pattern,
            ),
        identifier_pattern: $ =>
            prec.left(
                seq(
                    field("name", $.identifier),
                    optional(
                        seq(
                            ":",
                            field("type", $._expression),
                        )
                    ),
                    optional(
                        seq(
                            "=",
                            field("default", $._expression),
                        )
                    ),
                ),
            ),
        enum_pattern: $ =>
            prec.left(
                seq(
                    field("name", $.identifier),
                    field("arguments", $.tuple_pattern),
                ),
            ),
        literal_pattern: $ => $._literal,
        tuple_pattern: $ =>
            seq(
                "(",
                repeat(seq($._value_pattern, ",")),
                optional($._value_pattern),
                ")",
            ),

        //
        //  Statements
        //
        _statement: $ => choice(
            $.import,
            $._let,
            $.do,
            $.yield,
            $.return,
            $.if,
            $.if_let,
            $.each,
            $.each_range,
            $.match,
            $.retry_case,
            $.batch_attributes,
        ),
        import: $ =>
            seq(
                "import",
                field("module", $.qualified_identifier),
                // TODO Pattern import syntax
                // import renamed = foo
                // import (bar, baz) = foo
            ),
        do: $ =>
            prec.right(
                seq(
                    "do",
                    $._expression,
                ),
            ),
        yield: $ =>
            prec.right(
                seq(
                    "yield",
                    $._expression,
                ),
            ),
        return: $ =>
            prec.right(
                seq(
                    "return",
                    $._expression,
                ),
            ),
        if: $ =>
            prec.right(
                seq(
                    "if",
                    field("condition", $.tuple),
                    field("then", $._expression),
                    optional(
                        seq(
                            "else",
                            field("else", $._expression)
                        ),
                    )
                )
            ),
        if_let: $ =>
            prec.right(
                seq(
                    "if",
                    "let",
                    field("pattern", $.let_variable),
                    field("then",
                        choice(
                            $._statement,
                            $.block_expression,
                        )
                    ),
                    optional(
                        seq(
                            "else",
                            field("else", $._expression)
                        ),
                    )
                ),
            ),
        each: $ =>
            prec.right(
                seq(
                    "each",
                    field("pattern", $.let_variable),
                    field("then",
                        choice(
                            $._statement,
                            $.block_expression,
                        )
                    ),
                ),
            ),
        each_range: $ =>
            prec.right(
                seq(
                    "each",
                    "(",
                    field("pattern", $._value_pattern),
                    "in",
                    field("range", $._expression),
                    ")",
                    field("then", $._expression),
                ),
            ),
        match: $ =>
            seq(
                "match",
                field("expression", $.tuple),
                "{",
                field("case", repeat($.case)),
                "}",
            ),
        case: $ =>
            seq(
                "case",
                choice(
                    "default",
                    field("pattern", $._value_pattern),
                ),
                field("value",
                    choice(
                        seq(
                            "=",
                            $._expression,
                        ),
                        $.block_expression
                    ),
                ),
            ),
        retry_case: $ =>
            prec.right(
                seq(
                    "do",
                    "case",
                    $._expression,
                ),
            ),
        batch_attributes: $ =>
            prec.right(
                choice(
                    seq(
                        field("attributes", $._function_attributes),
                        ":",
                        repeat($._statement),
                    ),
                    seq(
                        field("attributes", $._function_attributes),

                        // Not a block: no new scope is created
                        "{",
                        repeat($._statement),
                        "}"
                    ),
                ),
            ),

        //
        //  Declarations (let)
        //
        _let: $ =>
            prec.right(
                seq(
                    "let",
                    choice(
                        $.let_variable,
                        $.let_function,
                        $.let_struct,
                        $.let_enum,
                    ),
                ),
            ),
        let_variable: $ =>
            prec.right(
                seq(
                    field("pattern", $._value_pattern),
                    "=",
                    field("value", $._expression),
                ),
            ),
        let_function: $ =>
            prec.right(
                seq(
                    field("name", $.identifier),
                    $.function_scope
                ),
            ),
        function_scope: $ =>
            prec.right(
                seq(
                    field("pattern", $.function_signature_pattern),
                    field("body",
                        choice(
                            $.block_expression,
                            seq(
                                "=",
                                $._expression,
                            ),
                        )
                    ),
                ),
            ),
        let_struct: $ =>
            prec.right(
                seq(
                    "struct",
                    $.enum_pattern,
                ),
            ),
        let_enum: $ =>
            prec.right(
                seq(
                    "enum",
                    field("name", $.identifier),
                    field("external", optional($.external)),
                    "{",
                    field("pattern", repeat($.enum_pattern)),
                    "}",
                ),
            ),
        external: $ =>
            seq(
                "external",
                optional(
                    seq(
                        "(",
                        field("module", $.string),
                        ")",
                    )
                ),
            ),

        //
        //  Literals
        //
        _literal: $ =>
            choice(
                $.string,
                $.integer
            ),
        string: $ => $._doubleQuotedString,
        _doubleQuotedString: $ =>
            seq(
                "\"",
                repeat(
                    choice(
                        token.immediate(/[^"\\]+/),
                        $.escapeSequence,
                    ),
                ),
                "\""
            ),
        escapeSequence:
            $ => seq("\\", /["n\\]/),
        _number: $ => $.integer,
        integer: $ => $._decimalInteger,
        _decimalInteger: $ => /[0-9][0-9_]*/,

        //
        // Comments
        //
        comment: $ => choice(
            seq("//", /.*/),
            seq("/*", /([^*]*|\*[^/])*/, "*/")
        ),
        _whitespace: $ => /\s+/,

    }
});
