// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <cstddef>
namespace cie_windows {
// Windows 7+ generic credential limit, also used by the Windows 10 SDK.
// Some MinGW wincred.h versions still define the pre-Windows-7 512-byte limit.
inline constexpr std::size_t credentialBlobLimit=5*512;
}
