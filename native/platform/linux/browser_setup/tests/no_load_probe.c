// SPDX-License-Identifier: BSD-3-Clause
// Test-only foreign module: its constructor must never run during setup.
#include <stdio.h>
#include <stdlib.h>
__attribute__((constructor)) static void initialized(void) {
  const char* path = getenv("CIE_SETUP_PROBE_MARKER");
  if (path) {
    FILE* output = fopen(path, "w");
    if (output) { fputs("loaded", output); fclose(output); }
  }
}
