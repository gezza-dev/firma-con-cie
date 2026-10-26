// SPDX-License-Identifier: BSD-3-Clause
#include "document_drop.h"

static void paths_before_portal_and_text() {
  GtkWidget* widget = gtk_event_box_new();
  g_object_ref_sink(widget);
  gtk_drag_dest_set(widget, GTK_DEST_DEFAULT_ALL, nullptr, 0, GDK_ACTION_COPY);
  cie_document_drop_prioritize_paths(widget);
  GtkTargetList* targets = gtk_drag_dest_get_target_list(widget);
  gint count = 0;
  GtkTargetEntry* table = gtk_target_table_new_from_list(targets, &count);
  g_assert_cmpint(count, ==, 3);
  g_assert_cmpstr(table[0].target, ==, "text/uri-list");
  g_assert_cmpstr(table[1].target, ==, "application/vnd.portal.filetransfer");
  g_assert_cmpstr(table[2].target, ==, "STRING");
  for (gint index = 0; index < count; ++index) {
    g_assert_cmpuint(table[index].flags, ==, GTK_TARGET_OTHER_APP);
    guint info = 99;
    g_assert_true(gtk_target_list_find(targets, gdk_atom_intern(table[index].target, FALSE), &info));
    g_assert_cmpuint(info, ==, 0);
  }
  gtk_target_table_free(table, count);
  gtk_widget_destroy(widget);
  g_object_unref(widget);
}

int main(int argc, char** argv) {
  g_test_init(&argc, &argv, nullptr);
  g_setenv("NO_AT_BRIDGE", "1", TRUE);
  gtk_init(&argc, &argv);
  g_test_add_func("/document-drop/paths-before-portal-and-text", paths_before_portal_and_text);
  return g_test_run();
}
