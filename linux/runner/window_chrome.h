// SPDX-License-Identifier: BSD-3-Clause
#ifndef CIE_LINUX_WINDOW_CHROME_H_
#define CIE_LINUX_WINDOW_CHROME_H_
#include <gtk/gtk.h>

G_DECLARE_FINAL_TYPE(CieWindowChrome, cie_window_chrome, CIE, WINDOW_CHROME, GObject)

// The header owns the returned reference. Its embedded icon is the only icon;
// window controls retain the desktop layout. Flatpak reads appearance via portal.
CieWindowChrome* cie_window_chrome_new(GtkHeaderBar* header, gboolean use_portal);
#endif
