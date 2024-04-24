# FluidTreeSitter

This package provides [Tree-sitter](https://tree-sitter.github.io/) integration for
[Fluid](https://git.samerion.com/Samerion/Fluid), so that Tree-sitter can be used to highlight syntax in `CodeInput`.
Compiles and links dependencies using ImportC.

Exposes Tree-sitter through the `lib_tree_sitter` module, and provides Fluid API in `fluid.tree_sitter`:

```
/*
"dependencies": {
    "fluid": "~>0.7"
    "fluid-tree-sitter": ">=0.0.0",
}
*/
import fluid.tree_sitter;

TSQueryError error;
uint errorOffset;

auto language = treeSitterLanguage!"json";
auto query = ts_query_new(language, queryString.ptr, queryString.length, &errorOffset, &error);
auto highlighter = new TreeSitterHighlighter(language, query);
auto editor = codeInput(highlighter);
```

In order to use a language with this package, parser for the language must be linked into program. Subpackage
`fluid-tree-sitter:d` can be used to load the D language parser via ImportC — exposing queries via `dQuerySource`.

```
/*
"dependencies": {
    "fluid": "~>0.7"
    "fluid-tree-sitter": ">=0.0.0",
    "fluid-tree-sitter:d": ">=0.0.0"
}
*/
import fluid.tree_sitter;

TSQueryError error;
uint errorOffset;

auto language = treeSitterLanguage!"d";
auto query = ts_query_new(language, dQuerySource.ptr, dQuerySource.length, &errorOffset, &error);
auto highlighter = new TreeSitterHighlighter(language, query);
auto editor = codeInput(highlighter);
```
