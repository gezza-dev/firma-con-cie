// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <cstddef>
// Annotation compatibility only. All data layouts/types come from the official
// CPDK header. The MinGW system v4 header is rejected below.
#ifdef __MINGW32__
#include <specstrings.h>
#pragma push_macro("__in")
#undef __in
#define __in
#pragma push_macro("__in_opt")
#undef __in_opt
#define __in_opt
#pragma push_macro("__inout")
#undef __inout
#define __inout
#pragma push_macro("__out")
#undef __out
#define __out
#pragma push_macro("__out_opt")
#undef __out_opt
#define __out_opt
#pragma push_macro("__in_bcount")
#undef __in_bcount
#define __in_bcount(x)
#pragma push_macro("__in_ecount")
#undef __in_ecount
#define __in_ecount(x)
#pragma push_macro("__out_bcount")
#undef __out_bcount
#define __out_bcount(x)
#pragma push_macro("__out_bcount_part_opt")
#undef __out_bcount_part_opt
#define __out_bcount_part_opt(x,y)
#pragma push_macro("__deref_opt_out_bcount")
#undef __deref_opt_out_bcount
#define __deref_opt_out_bcount(x)
#pragma push_macro("__deref_out_bcount")
#undef __deref_out_bcount
#define __deref_out_bcount(x)
#pragma push_macro("__deref_out_bcount_opt")
#undef __deref_out_bcount_opt
#define __deref_out_bcount_opt(x)
#pragma push_macro("__deref_out_ecount")
#undef __deref_out_ecount
#define __deref_out_ecount(x)
#endif
extern "C" {
#include <cardmod.h>
}
#ifdef __MINGW32__
#pragma pop_macro("__deref_out_ecount")
#pragma pop_macro("__deref_out_bcount_opt")
#pragma pop_macro("__deref_out_bcount")
#pragma pop_macro("__deref_opt_out_bcount")
#pragma pop_macro("__out_bcount_part_opt")
#pragma pop_macro("__out_bcount")
#pragma pop_macro("__in_ecount")
#pragma pop_macro("__in_bcount")
#pragma pop_macro("__out_opt")
#pragma pop_macro("__out")
#pragma pop_macro("__inout")
#pragma pop_macro("__in_opt")
#pragma pop_macro("__in")
#endif
#ifndef CARD_DATA_VERSION_SEVEN
#error "CPDK cardmod.h v7 is required; the MinGW v4 header is insufficient"
#endif
static_assert(sizeof(void*)==8,"Windows x64 only");
static_assert(sizeof(CARD_KEY_HANDLE)==8,"Cardmod pointer-sized key handle");
static_assert(offsetof(CARD_DATA,pfnCardDeleteContext)==120,"Cardmod x64 callback ABI");
static_assert(sizeof(CONTAINER_MAP_RECORD)==86,"Cardmod container map wire layout");
