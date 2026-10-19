// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <podofo/podofo.h>
namespace cie {
void setSignatureAppearance(PoDoFo::PdfDocument& document, PoDoFo::PdfSignature& signature,
    const PoDoFo::Rect& rectangle, const char* image, const char* description, const char* date);
}
