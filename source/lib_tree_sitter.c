// D wrapper over tree-sitter
// Compiles Tree Sitter with DMD & ImportC
#define _POSIX_C_SOURCE 200112L
#define TREE_SITTER_ATOMIC_H_

__import core.atomic;

static inline size_t atomic_load(const volatile size_t *p) {
  return atomicLoad(*p);
}

static inline uint32_t atomic_inc(volatile uint32_t *p) {
  return atomicFetchAdd(*p, 1) + 1;
}

static inline uint32_t atomic_dec(volatile uint32_t *p) {
  return atomicFetchSub(*p, 1) - 1;
}

#define ts_malloc  malloc
#define ts_calloc  calloc
#define ts_realloc realloc
#define ts_free    free

#include "../external/tree-sitter/lib/include/tree_sitter/api.h"
#include "../external/tree-sitter/lib/src/get_changed_ranges.c"
#include "../external/tree-sitter/lib/src/language.c"
#include "../external/tree-sitter/lib/src/lexer.c"
#include "../external/tree-sitter/lib/src/node.c"
#include "../external/tree-sitter/lib/src/parser.c"
#include "../external/tree-sitter/lib/src/query.c"
#include "../external/tree-sitter/lib/src/stack.c"
#define ts_subtree_new_node ts_subtree_new_node_disabled
#include "../external/tree-sitter/lib/src/subtree.c"
#undef ts_subtree_new_node
#include "../external/tree-sitter/lib/src/tree_cursor.c"
#include "../external/tree-sitter/lib/src/tree.c"
#include "../external/tree-sitter/lib/src/wasm.c"


// This function is overwritten as a workaround for https://issues.dlang.org/show_bug.cgi?id=24495
// The old function is still used in subtree.c, however it is not used there in a way that would meaningfully trigger
// the bug
MutableSubtree ts_subtree_new_node(
  TSSymbol symbol,
  SubtreeArray *children,
  unsigned production_id,
  const TSLanguage *language
) {
  TSSymbolMetadata metadata = ts_language_symbol_metadata(language, symbol);
  bool fragile = symbol == ts_builtin_sym_error || symbol == ts_builtin_sym_error_repeat;

  // Allocate the node's data at the end of the array of children.
  size_t new_byte_size = ts_subtree_alloc_size(children->size);
  if (children->capacity * sizeof(Subtree) < new_byte_size) {
    children->contents = ts_realloc(children->contents, new_byte_size);
    children->capacity = (uint32_t)(new_byte_size / sizeof(Subtree));
  }
  SubtreeHeapData *data = (SubtreeHeapData *)&children->contents[children->size];

  *data = (SubtreeHeapData) {
    .ref_count = 1,
    .symbol = symbol,
    .child_count = children->size,
    .visible = metadata.visible,
    .named = metadata.named,
    .has_changes = false,
    .has_external_scanner_state_change = false,
    .fragile_left = fragile,
    .fragile_right = fragile,
    .is_keyword = false,
    .visible_descendant_count = 0,
    .production_id = production_id,
    .first_leaf = {.symbol = 0, .parse_state = 0},
  };
  MutableSubtree result = {.ptr = data};
  ts_subtree_summarize_children(result, language);
  return result;
}
