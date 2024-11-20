/// [Tree Sitter](https://tree-sitter.github.io/) integration for [Fluid](https://git.samerion.com/Samerion/Fluid).
/// Provides syntax highlighting based on Tree Sitter grammars for use in `CodeInput`.
module fluid.tree_sitter;

import lib_tree_sitter;

import std.uni;
import std.range;
import std.string;
import std.algorithm;

import fluid.text;
import fluid.code_input;

public import lib_tree_sitter : TSLanguage, TSQuery, TSQueryError, ts_query_new, ts_query_delete;


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

version (FluidTreeSitter_DisableBuiltInQueries) { }
else {

    // Load queries for included dependencies
    immutable smaugQuerySource = join([
        import("tree-sitter-smaug/queries/highlights.scm"),
    ]);

    immutable dQuerySource = join([
        import("tree-sitter-d/queries/highlights.scm"),
    ]);

}


@safe:


/// Provides syntax highlighting for CodeInput through Tree Sitter.
class TreeSitterHighlighter : CodeHighlighter {

    public {

        TSLanguage* language;
        TSQuery* _query;

        CodeToken[string] palette;
        string[256] paletteNames;
        IndexedCodeSlice[] highlighterSlices;

    }

    private struct IndexedCodeSlice {

        CodeSlice slice;
        uint patternIndex;

        alias slice this;

        ptrdiff_t opCmp(const IndexedCodeSlice other) const {

            auto cmp = slice.opCmp(other.slice);

            if (cmp) return cmp;

            // If the delimiters have the same offset, sort them so the last patterns come up first
            return other.patternIndex - patternIndex;

        }

    }

    private {

        /// Current text.
        Rope text;

        TSParser* _parser;
        TSTree* _tree;
        TSQueryCursor* _cursor;
        size_t _lastRangeIndex;
        size_t _lastIndex;
        CodeToken _paletteSize;

        /// True after the value changes. Indicates TS queries have to be rerun.
        bool isUpdatePending;

    }

    /// Create a highlighter using a TSLanguage* and relevant highlight query.
    this(TSLanguage* language, TSQuery* query) @trusted {

        this.language = language;
        this._query = query;
        this._parser = ts_parser_new();
        this._cursor = ts_query_cursor_new();

        ts_parser_set_language(_parser, language);

    }

    ~this() @trusted {

        ts_parser_delete(_parser);
        ts_query_cursor_delete(_cursor);
        if (_tree) ts_tree_delete(_tree);

    }

    /// Get the tree from the parser. The tree may be deleted whenever the node triggers an update.
    TSTree* tree() @system {

        return _tree;

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

    void parse(Rope text, TextInterval start, TextInterval oldEnd, TextInterval newEnd) @trusted {

        import std.conv;

        this.text = text;

        // Delete previous tree
        if (_tree) {
            TSInputEdit edit;
            edit.start_byte = cast(uint) start.length;
            edit.start_point.row = cast(uint) start.line;
            edit.start_point.column = cast(uint) start.column;
            edit.old_end_byte = cast(uint) oldEnd.length;
            edit.old_end_point.row = cast(uint) oldEnd.line;
            edit.old_end_point.column = cast(uint) oldEnd.column;
            edit.new_end_byte = cast(uint) newEnd.length;
            edit.new_end_point.row = cast(uint) newEnd.line;
            edit.new_end_point.column = cast(uint) newEnd.column;
            ts_tree_edit(_tree, &edit);
        }

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
        _tree = ts_parser_parse(_parser, _tree, input);
        isUpdatePending = true;

    }

    /// Run Tree Sitter queries.
    ///
    /// Does nothing if the value hasn't changed since the last call.
    private void runQueries() @trusted {

        // Ignore if there's nothing to update
        if (!isUpdatePending) return;

        auto root = ts_tree_root_node(_tree);

        // Delete the slices
        // TODO Reuse as much as possible
        highlighterSlices.length = 0;
        isUpdatePending = false;

        scope (success) highlighterSlices.sort!("a < b", SwapStrategy.stable);

        // Run the query, find all matches
        ts_query_cursor_exec(_cursor, _query, root);

        // Check each match
        TSQueryMatch match;

        while (ts_query_cursor_next_match(_cursor, &match)) {

            auto captures = match.captures[0 .. match.capture_count];

            foreach (capture; captures) {

                // Save the range for this node
                const start = ts_node_start_byte(capture.node);
                const end = ts_node_end_byte(capture.node);

                // Get the name
                uint nameLen;
                auto namePtr = ts_query_capture_name_for_id(_query, capture.index, &nameLen);
                const name = namePtr[0 .. nameLen];

                // Highlight token
                const token = tokenForCaptureName(name);

                highlighterSlices ~= IndexedCodeSlice(
                    CodeSlice(start, end, token),
                    match.pattern_index,
                );
                continue;

            }

        }

    }

    CodeSlice query(size_t firstIndex)
    in (false)
    do {

        runQueries();

        auto result = highlighterSlices
            .filter!(a => a.start != a.end)
            .find!(a => a.start >= firstIndex);

        if (result.empty)
            return CodeSlice();

        // Get the item with the lowest start value
        else
            return result.front;

    }

    string treeToString() @trusted {

        auto root = ts_tree_root_node(_tree);
        auto str = ts_node_string(root);
        scope (exit) free(str);

        return str.fromStringz.idup;

    }

}

///
@system
unittest {

    import std.file : readText;

    TSQueryError error;
    uint errorOffset;

    const queries = dQuerySource;

    // Load the language and corresponding queries
    auto language = treeSitterLanguage!"d";
    auto query = ts_query_new(language, queries.ptr, cast(uint) queries.length, &errorOffset, &error);
    scope (exit) ts_query_delete(query);

    // Create the highlighter
    auto highlighter = new TreeSitterHighlighter(language, query);

    // Create the input
    auto root = codeInput(highlighter);

}

version (Have_fluid_tree_sitter_smaug):
version (unittest):

// Unit test helpers
private {

    import std.meta : AliasSeq;

    TSQuery* dQuery;
    TSQuery* smaugQuery;

    static this() @system {

        import std.file : readText;

        TSQueryError error;
        uint errorOffset;

        dQuery = ts_query_new(treeSitterLanguage!"d", dQuerySource.ptr, cast(uint) dQuerySource.length,
            &errorOffset, &error);

        assert(dQuery, format!"%s at %s in D queries"(error, errorOffset));

        smaugQuery = ts_query_new(treeSitterLanguage!"smaug", smaugQuerySource.ptr, cast(uint) smaugQuerySource.length,
            &errorOffset, &error);

        assert(smaugQuery, format!"%s at %s in Smaug queries"(error, errorOffset));

    }

    static ~this() @system {

        ts_query_delete(dQuery);
        ts_query_delete(smaugQuery);

    }

    template trusted(alias fun) {

        auto trusted(Args...)(Args args) @trusted {

            return fun(args);

        }

    }
}

unittest {

    auto highlighter = new TreeSitterHighlighter(trusted!(treeSitterLanguage!"d"), dQuery);
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
    const end = TextInterval(source);
    highlighter.parse(source, TextInterval.init, end, end);

    // Test some specific tokens in order
    auto range = highlighter.save;
    range = range.find(slice("import", keyword));
    range = range.find(slice("void", type));
    range = range.find(slice("main", function_));
    range = range.find(slice(`"Hello, World!"`, string_));
    assert(!range.empty);

}

unittest {

    auto highlighter = new TreeSitterHighlighter(trusted!(treeSitterLanguage!"smaug"), smaugQuery);
    auto source = Rope(`
        import smaug.io

        let main() yield IO {
            do writeln("Hello, World!")
        }
    `);

    TextStyleSlice slice(string word, ubyte token) {

        const index = source.indexOf(word);

        return TextStyleSlice(index, index + word.length, token);

    }

    const keyword = highlighter.tokenForCaptureName("keyword");
    const type = highlighter.tokenForCaptureName("type");
    const attribute = highlighter.tokenForCaptureName("attribute");
    const function_ = highlighter.tokenForCaptureName("function");
    const string_ = highlighter.tokenForCaptureName("string");

    // Load the source
    const end = TextInterval(source);
    highlighter.parse(source, TextInterval.init, end, end);

    // Test some specific tokens in order
    auto range = highlighter.save;

    range = range.find(slice("import", keyword));
    range = range.find(slice("let", keyword));
    range = range.find(slice("main", function_));
    range = range.find(slice("yield", attribute));
    range = range.find(slice("IO", type));
    range = range.find(slice("writeln", function_));
    range = range.find(slice(`"Hello, World!"`, string_));
    assert(!range.empty);

}
