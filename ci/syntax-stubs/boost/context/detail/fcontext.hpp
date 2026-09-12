#pragma once
// Syntax-only shim - see ../../../README.md. Cemu's fiber implementation uses
// boost.context on some platforms; the signatures are all it needs here.
#include <cstddef>
namespace boost { namespace context { namespace detail {
typedef void* fcontext_t;
struct transfer_t { fcontext_t fctx; void* data; };
extern "C" transfer_t jump_fcontext(fcontext_t const, void*);
extern "C" fcontext_t make_fcontext(void*, std::size_t, void (*)(transfer_t));
extern "C" transfer_t ontop_fcontext(fcontext_t const, void*, transfer_t (*)(transfer_t));
}}}
