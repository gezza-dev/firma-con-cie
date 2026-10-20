// SPDX-License-Identifier: BSD-3-Clause
#ifndef CIE_LINUX_WINDOW_SIZING_H_
#define CIE_LINUX_WINDOW_SIZING_H_

#include <gtk/gtk.h>

struct CieWindowSize {
  int width;
  int height;
  int available_width;
  int available_height;
  bool maximize;
};

// All inputs/outputs are GTK application pixels, already scaled by GDK.
// No font scale, device pixel ratio or GDK scale factor belongs in this policy.
CieWindowSize cie_window_size_for_area(int width, int height, int titlebar_height);

// Window-owned observers: initial fit and updates on monitor/workarea changes.
// Resizing/maximization is negotiated with the compositor; never fullscreen.
void cie_window_sizing_attach(GtkWindow* window);

#endif  // CIE_LINUX_WINDOW_SIZING_H_
