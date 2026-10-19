// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <stdint.h>
// Additive ABI v1. Configuration is scoped to this call, never process-global.
// Mutable password is wiped on every exit. No persistence or environment fallback.
typedef struct CieNetworkOptions {
 uint32_t size;
 int32_t mode;
 const char* host;
 int32_t port;
 const char* username;
 char* password;
} CieNetworkOptions;
typedef struct CieNetworkProbe {
 uint32_t size;
 int32_t transport_code;
 int32_t http_status;
} CieNetworkProbe;
