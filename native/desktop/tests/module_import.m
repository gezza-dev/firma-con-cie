// SPDX-License-Identifier: BSD-3-Clause
// Check the public Clang module used by Swift, without AppKit or a window.
@import CieWindowGeometry;

int main(void) {
  CieWindowRect rect = {0, 0, 1080, 788};
  CieWindowRect work = {-100, 20, 900, 600};
  return cie_window_valid_rect(cie_window_fit_rect(rect, work)) ? 0 : 1;
}
