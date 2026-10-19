// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include "cie_document_types.h"
#include <cmath>
namespace cie_pdf {
inline bool valid(const CiePdfAppearance& a) {
    return a.size == sizeof(a) && a.page >= 0 && a.page < 100000 && a.imagePath && *a.imagePath &&
        std::isfinite(a.left) && std::isfinite(a.top) && std::isfinite(a.width) && std::isfinite(a.height) &&
        a.left >= 0 && a.top >= 0 && a.width > 0 && a.height > 0 &&
        a.left + a.width <= 1.000001 && a.top + a.height <= 1.000001;
}
}
