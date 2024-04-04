/// [Tree Sitter](https://tree-sitter.github.io/) integration for [Fluid](https://git.samerion.com/Samerion/Fluid).
/// Provides syntax highlighting and automatic indents based on Tree Sitter grammars for use in `CodeInput`.
///
/// Note that automatic indents use Fluid-specific queries that aren't compatible with other editors such as
/// [nvim](https://github.com/nvim-treesitter/nvim-treesitter). The implementation is, however, compatible with queries
/// provided by [the D grammar for Tree Sitter](https://github.com/gdamore/tree-sitter-d)
module fluid.tree_sitter;

import fluid_tree_sitter_c;

import std.uni;
import std.range;
import std.string;
import std.algorithm;

import fluid.text;
import fluid.code_input;


/// Get TSLanguage for language with the given name. This template creates a binding for the grammar's C entrypoint,
/// such as `tree_sitter_d` or `tree_sitter_javascript`.
///
/// The grammar must be linked into this program. The name will
/// typically use `snake_case` (lowercase characters, words separated by underscores).
template treeSitterLanguage(string name) {

    extern (C)
    pragma(mangle, "tree_sitter_" ~ name)
    TSLanguage* treeSitterLanguage() @system;

}

/// Create a `TreeSitterHighlighter` using given language (see `treeSitterLanguage`) and query files. The grammar must
/// be linked into this program. Given query files will be loaded from the filesystem and used by the highlighter.
TreeSitterHighlighter treeSitterHighlighter(string language)(string[] queryFiles...) @system {

    import std.file : readText;

    auto tsl = treeSitterLanguage!language;
    const queries = queryFiles.map!(a => a.readText).join;

    return new TreeSitterHighlighter(tsl, queries);

}


@safe:


/// Provides syntax highlighting and indenting for CodeInput through Tree Sitter.
class TreeSitterHighlighter : CodeHighlighter, CodeIndentor {

    public {

        TSParser* parser;
        TSLanguage* language;
        TSTree* tree;

        CodeToken[string] palette;
        string[256] paletteNames;
        CodeSlice[] highlighterSlices;

    }

    private struct Line {

        ptrdiff_t firstDelimiter;
        int indent;

        ptrdiff_t opCmp(const Line other) const {

            return firstDelimiter - other.firstDelimiter;

        }

        ptrdiff_t opCmp(const ptrdiff_t otherDelimiter) const {

            return firstDelimiter - otherDelimiter;

        }

    }

    private struct Delimiter {

        ptrdiff_t offset;
        int change;
        TSPoint point;
        bool whole;

        ptrdiff_t opCmp(const Delimiter other) const {

            return offset - other.offset;

        }

        ptrdiff_t opCmp(const ptrdiff_t otherOffset) const {

            return offset - otherOffset;

        }

    }

    private {

        /// Current text.
        Rope text;

        TSQueryCursor* _cursor;
        TSQuery* _query;
        size_t _lastRangeIndex;
        size_t _lastIndex;
        CodeToken _paletteSize;

        /// Lines, used by `loadIndents` — omits lines without indent delimiters, and has offsets for the first
        /// delimiter of each line, rather than the line's start.
        SortedRange!(Line[]) _lines;

    }

    /// Create a highlighter using a TSLanguage* and a query file. Unlike `treeSitterLanguage`, takes file content
    /// rather than file paths.
    this(TSLanguage* language, string queries) @trusted {

        uint offset;
        TSQueryError error;

        this.parser = ts_parser_new();
        this.language = language;
        this._query = ts_query_new(language, queries.ptr, cast(uint) queries.length, &offset, &error);
        this._cursor = ts_query_cursor_new();

        if (_query is null)
            throw new Exception(format!"TreeSitter query error: %s"(error));

        ts_parser_set_language(parser, language);

    }

    ~this() @trusted {

        ts_parser_delete(parser);
        ts_language_delete(language);
        ts_query_delete(_query);
        ts_query_cursor_delete(_cursor);
        if (tree) ts_tree_delete(tree);

    }

    const(char)[] nextTokenName(CodeToken index) {

        return paletteNames[index];

    }

    CodeToken tokenForCaptureName(const(char)[] value) {

        // Token exists
        if (auto token = value in palette) {

            return *token;

        }

        const index = ++_paletteSize;

        // Create a new entry if not
        auto name = paletteNames[index] = value.idup;
        return palette[name] = index;

    }

    void parse(Rope text) @trusted {

        import std.conv;

        this.text = text;

        // Delete previous tree
        // TODO Use ts_tree_edit instead
        if (tree) ts_tree_delete(tree);
        tree = null;

        // Make the rope readable by TreeSitter
        TSInput input;
        input.payload = &text;
        input.encoding = TSInputEncoding.TSInputEncodingUTF8;
        input.read = function (payload, byteOffset, position, bytesRead) {

            auto text = *cast(Rope*) payload;
            auto result = text.leafFrom(byteOffset).value;

            *bytesRead = cast(uint) result.length;
            return result.ptr;

        };

        // Create the tree
        tree = ts_parser_parse(parser, tree, input);

        runQueries();

    }

    /// Run Tree Sitter queries.
    private void runQueries() @trusted {

        Delimiter wholeIndent(ptrdiff_t offset, int change, TSPoint point) {

            return Delimiter(offset, change, point, true);

        }

        auto root = ts_tree_root_node(tree);
        auto rootStart = ts_node_start_point(root);
        auto rootEnd = ts_node_end_point(root);

        // Run the query, find all matches
        ts_query_cursor_exec(_cursor, _query, root);

        // Delete the slices
        // TODO Reuse as much as possible
        highlighterSlices.length = 0;

        auto delimiters = appender!(Delimiter[]);
        bool[ptrdiff_t] excludedIndents;

        scope (success) loadIndents(delimiters[]);

        // Check each match
        TSQueryMatch match;
        while (ts_query_cursor_next_match(_cursor, &match)) {

            auto captures = match.captures[0 .. match.capture_count];

            foreach (capture; captures) {

                // Save the range for this node
                const start = ts_node_start_byte(capture.node);
                const end = ts_node_end_byte(capture.node);
                const startPoint = ts_node_start_point(capture.node);
                const endPoint = ts_node_end_point(capture.node);

                // Get the name
                uint nameLen;
                auto namePtr = ts_query_capture_name_for_id(_query, capture.index, &nameLen);
                const name = namePtr[0 .. nameLen];

                switch (name) {

                    // Indent tokens
                    case "indent.begin":
                        delimiters ~= Delimiter(end, +1, endPoint);
                        break;
                    case "indent.end":
                        // TreeSitter attempts to fix up mismatching braces and it messes with the indents
                        if (start == text.length) break;
                        delimiters ~= Delimiter(start, -1, startPoint);
                        break;
                    case "indent.exclude":
                        excludedIndents[start] = true;
                        excludedIndents[end] = true;
                        break;
                    case "indent.whole":
                        delimiters ~= wholeIndent(start, +1, startPoint);
                        delimiters ~= wholeIndent(end, -1, endPoint);
                        break;

                    // Highlight token
                    default:

                        const token = tokenForCaptureName(name);

                        highlighterSlices ~= CodeSlice(start, end, token);
                        break;

                }

            }

        }

    }

    private void loadIndents(Delimiter[] delimiters, bool[ptrdiff_t] excludedIndents = null) {

        auto lines = appender!(Line[]);

        // Sort the delimiters
        auto delimitersByLine = sort(delimiters[])
            .chunkBy!((a, b) => a.point.row == b.point.row);

        // Keep a stack of open delimiters; track their start lines
        size_t[] stack;

        // Indent to use for the next line
        int nextIndent;

        // Iterate on each delimiter, grouped by lines
        // Note: Line indices don't match their numbers precisely; lines without any delimiters will be omitted.
        foreach (lineIndex, line; delimitersByLine.enumerate) {

            const firstDelimiter = line.front;

            // Balance of delimiters on this line, used to determine initial indent for the next line
            int balance;

            foreach (delimiter; line) {

                // Ignore delimiters marked with @indent.exclude
                if (delimiter.whole && delimiter.offset in excludedIndents) continue;

                balance += delimiter.change;

                // Start delimiter, push to stack
                if (delimiter.change == +1) {

                    stack ~= lineIndex;

                }

                // End delimiter
                else if (delimiter.change == -1) {

                    const pairedLine = stack.back;
                    stack.popBack;

                    // Go back to the indent of the start delimiter
                    if (pairedLine != lineIndex)
                        nextIndent = lines[][pairedLine].indent - 1;

                }

            }

            if (balance > 0)
                nextIndent += 1;

            // Add an entry for this line
            // Queries for each line will ask for the first non-space character and will not be affected
            // by the entry if the delimiter is not the first thing on the line; this is indended.
            lines ~= Line(firstDelimiter.offset, nextIndent);

        }

        _lines = assumeSorted(lines[]);

    }

    CodeSlice query(size_t firstIndex)
    in (false)
    do {

        auto result = highlighterSlices
            .filter!(a => a.start != a.end)
            .find!(a => a.start >= firstIndex);

        if (result.empty)
            return CodeSlice();
        else
            return result.front;

    }

    int indentLevel(ptrdiff_t offset) {

        auto results = _lines.trisect(offset);

        // Exact match
        if (!results[1].empty)
            return results[1].back.indent;

        // Found something
        if (!results[0].empty)
            return results[0].back.indent;

        // No relevant indent
        return 0;

    }

    int indentDifference(ptrdiff_t offset) {

        // Find the previous line
        const lineStart = text.lineStartByIndex(offset);
        const previousLineEnd = text[0 .. lineStart].chomp.length;
        const previousHome = previousLineEnd - text.lineByIndex(previousLineEnd).find!(a => !a.isWhite).length;

        return indentLevel(offset) - indentLevel(previousHome);

    }

}

///
@system
unittest {

    import std.file : readText;

    // Load the language and corresponding queries
    // Note: This is @system
    auto highlighter = treeSitterHighlighter!"d"(
        "external/tree-sitter-d/queries/highlights.scm",
        "external/tree-sitter-d/queries/indents.scm",
    );

    // Create the input
    auto root = codeInput(highlighter);

}

// Unit test helpers
version (unittest) private {

    import std.meta : AliasSeq;

    enum dQueries = AliasSeq!(
        "external/tree-sitter-d/queries/highlights.scm"
    );
    enum smaugQueries = AliasSeq!(
        "external/tree-sitter-smaug/queries/highlights.scm",
        "external/tree-sitter-smaug/queries/indents.scm",
    );

    template trusted(alias fun) {

        auto trusted(Args...)(Args args) @trusted {

            return fun(args);

        }

    }
}

unittest {

    auto highlighter = trusted!(treeSitterHighlighter!"d")(dQueries);
    auto source = Rope(q{
        import std.stdio;

        void main() {

            writeln("Hello, World!");

        }
    });

    TextStyleSlice slice(string word, ubyte token) {

        const index = source.indexOf(word);

        return TextStyleSlice(index, index + word.length, token);

    }

    const keyword = highlighter.tokenForCaptureName("keyword");
    const type = highlighter.tokenForCaptureName("type");
    const function_ = highlighter.tokenForCaptureName("function");
    const string_ = highlighter.tokenForCaptureName("string");

    // Load the source
    highlighter.parse(source);

    // Test some specific tokens in order
    auto range = highlighter.save;
    range = range.find(slice("import", keyword));
    range = range.find(slice("void", type));
    range = range.find(slice("main", function_));
    range = range.find(slice(`"Hello, World!"`, string_));
    assert(!range.empty);

}

unittest {

    import std.conv : to;
    import std.ascii : isDigit;
    import fluid.typeface : Typeface;

    auto highlighter = trusted!(treeSitterHighlighter!"smaug")(smaugQueries);
    auto source = Rope(`
        let foo() {       // 0
                          // 1
            do call()     // 1
            do call(foo,  // 1
                bar)      // 2
            do call(      // 1
            )             // 1
            do call((     // 1
            ))            // 1
            do foo(       // 1
                stuff(    // 2
                    abc)  // 3
            )             // 1
            do call( (    // 1
            ) )           // 1
            do            // 1
              call()      // 2
                          // 1
        }                 // 0
    `);

    highlighter.parse(source);

    int previousIndent = 0;

    foreach (i, line; Typeface.lineSplitterIndex(source)) {

        if (!line.byDchar.endsWith!isDigit) return;

        const expectedIndent = line.retro.until("//").array.strip.retro.to!int;
        auto lineHome = i + line.until!(a => a != ' ').walkLength;

        assert(highlighter.indentLevel(lineHome) == expectedIndent);
        assert(highlighter.indentDifference(lineHome) == expectedIndent - previousIndent);

        previousIndent = expectedIndent;

    }

}
