// SPDX-License-Identifier: BSD-3-Clause
#include "../window_geometry.h"

#include <assert.h>
#include <stdio.h>

static void same(CieWindowRect a, CieWindowRect b) {
  assert(a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height);
}

int main(void) {
  const CieWindowRect mac_visible = {0, 80, 1280, 696};
  const CieWindowRect mac_preferred_frame = {100, 100, 1080, 788};
  const CieWindowRect mac_expected = {100, 80, 1080, 696};
  same(cie_window_fit_rect(mac_preferred_frame, mac_visible), mac_expected);
  // Retina backing pixels are intentionally absent: the same AppKit points
  // yield identical fitting at 1x and 2x. Small user windows retain their size.
  const CieWindowRect small = {100, 120, 700, 420};
  same(cie_window_fit_rect(small, mac_visible), small);
  const CieWindowRect left_monitor = {-1920, -40, 1920, 1040};
  const CieWindowRect off_left = {-2100, 900, 1280, 720};
  const CieWindowRect expected_left = {-1920, 280, 1280, 720};
  same(cie_window_fit_rect(off_left, left_monitor), expected_left);
  for (unsigned dpi = 96; dpi <= 192; dpi += 24) {
    const double width = cie_window_scale_96(1280, dpi);
    const double height = cie_window_scale_96(720, dpi);
    const CieWindowRect requested = {10, 10, width, height};
    const CieWindowRect work = {0, 0, 1920, 1040};
    const CieWindowRect fitted = cie_window_fit_rect(requested, work);
    assert(fitted.width == fmin(width, 1920));
    assert(fitted.height == fmin(height, 1040));
    // A WM_DPICHANGED suggestion is already scaled; fitting must be idempotent.
    same(cie_window_fit_rect(fitted, work), fitted);
  }
  assert(cie_window_scale_96(1280, 0) == 1280);
  const CieWindowRect windows_suggested = {1920, 20, 1600, 900};
  const CieWindowRect right_work = {1920, 40, 1920, 1040};
  const CieWindowRect right_expected = {1920, 40, 1600, 900};
  same(cie_window_fit_rect(windows_suggested, right_work), right_expected);
  // Monitor removal and workarea reduction constrain both origin and size.
  const CieWindowRect reduced = {32, 30, 800, 450};
  same(cie_window_fit_rect(windows_suggested, reduced), reduced);
  const CieWindowRect fractional = {-20.5, 30.25, 900.5, 600.25};
  same(cie_window_fit_rect(fractional, fractional), fractional);
  const CieWindowRect invalid = {0, 0, 0, 0};
  same(cie_window_fit_rect(small, invalid), small);
  const CieWindowRect malformed = {NAN, 0, 100, 100};
  same(cie_window_fit_rect(malformed, mac_visible), mac_visible);
  for (int x = -4000; x <= 4000; x += 1000)
    for (int y = -2000; y <= 2000; y += 1000)
      for (int width = 400; width <= 2000; width += 400) {
        const CieWindowRect area = {(double)x, (double)y, (double)width, 700};
        const CieWindowRect candidate = {(double)x - 100, (double)y + 300, 1280, 760};
        const CieWindowRect fit = cie_window_fit_rect(candidate, area);
        assert(fit.x >= area.x && fit.y >= area.y);
        assert(fit.x + fit.width <= area.x + area.width);
        assert(fit.y + fit.height <= area.y + area.height);
        same(cie_window_fit_rect(fit, area), fit);
      }
  puts("Desktop geometry passed: AppKit points, DPI 96..192, suggested rectangles,"
       " negative/fractional origins, monitor/workarea reduction and invalid areas.");
  return 0;
}
