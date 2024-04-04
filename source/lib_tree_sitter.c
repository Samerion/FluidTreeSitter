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
#include "../external/tree-sitter/lib/src/subtree.c"
#include "../external/tree-sitter/lib/src/tree_cursor.c"
#include "../external/tree-sitter/lib/src/tree.c"
#include "../external/tree-sitter/lib/src/wasm_store.c"
