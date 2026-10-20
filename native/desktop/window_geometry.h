// SPDX-License-Identifier: BSD-3-Clause
#ifndef CIE_DESKTOP_WINDOW_GEOMETRY_H_
#define CIE_DESKTOP_WINDOW_GEOMETRY_H_

#include <math.h>
#include <stdbool.h>

// Native coordinate units throughout: AppKit points on macOS, physical pixels
// in a PerMonitorV2 Win32 window. Fitting never performs DPI/Retina conversion.
typedef struct CieWindowRect {
  double x;
  double y;
  double width;
  double height;
} CieWindowRect;

static inline bool cie_window_valid_rect(CieWindowRect rect) {
  return isfinite(rect.x) && isfinite(rect.y) && isfinite(rect.width) &&
         isfinite(rect.height) && rect.width > 0 && rect.height > 0 &&
         isfinite(rect.x + rect.width) && isfinite(rect.y + rect.height);
}

static inline CieWindowRect cie_window_fit_rect(CieWindowRect rect,
                                               CieWindowRect workarea) {
  if (!cie_window_valid_rect(workarea)) return rect;
  if (!cie_window_valid_rect(rect)) return workarea;
  rect.width = fmin(rect.width, workarea.width);
  rect.height = fmin(rect.height, workarea.height);
  rect.x = fmax(workarea.x, fmin(rect.x, workarea.x + workarea.width - rect.width));
  rect.y = fmax(workarea.y, fmin(rect.y, workarea.y + workarea.height - rect.height));
  return rect;
}

// Only logical Win32 preferences use this conversion, once at creation/minima.
// WM_DPICHANGED rectangles and monitor workareas must never pass through it.
static inline double cie_window_scale_96(double logical, unsigned int dpi) {
  return logical * (dpi ? dpi : 96) / 96.0;
}

#endif  // CIE_DESKTOP_WINDOW_GEOMETRY_H_
