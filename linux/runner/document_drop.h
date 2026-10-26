// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <gtk/gtk.h>
#include <initializer_list>

inline void cie_document_drop_prioritize_paths(GtkWidget* view) {
  // desktop_drop prefers a portal token and then STRING over file URIs.
  // Native/AppImage apps can use the explicit paths from GNOME/KDE directly;
  // retain the portal for sources that offer no URI list, without replacing
  // the plugin's data handlers or changing the transfer action.
  GtkTargetList* targets = gtk_target_list_new(nullptr, 0);
  for (const char* name : {"text/uri-list", "application/vnd.portal.filetransfer", "STRING"}) {
    gtk_target_list_add(targets, gdk_atom_intern(name, FALSE), GTK_TARGET_OTHER_APP, 0);
  }
  gtk_drag_dest_set_target_list(view, targets);
  gtk_target_list_unref(targets);
}
