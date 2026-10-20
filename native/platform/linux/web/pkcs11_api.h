// SPDX-License-Identifier: BSD-3-Clause
#pragma once
// Use the existing RSA Cryptoki declarations without adding their directory
// to the include search path: it also contains a legacy wintypes.h which must
// not shadow pcsc-lite's Unix types.
#include "../../../backend/cie-pkcs11/PKCS11/cryptoki.h"
