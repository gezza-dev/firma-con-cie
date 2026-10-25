// SPDX-License-Identifier: BSD-3-Clause
#include "window_chrome.h"
#include <functional>
#include <cstring>

static void wait_for(const std::function<bool()>& ready) {
  const auto deadline = g_get_monotonic_time() + 3000000;
  while (!ready() && g_get_monotonic_time() < deadline) {
    while (g_main_context_iteration(nullptr, FALSE)) {}
    g_usleep(1000);
  }
  g_assert_true(ready());
}
static gboolean dark() {
  gboolean value = FALSE;
  g_object_get(gtk_settings_get_default(), "gtk-application-prefer-dark-theme", &value, nullptr);
  return value;
}
static GtkHeaderBar* header(gboolean portal) {
  auto* bar = GTK_HEADER_BAR(gtk_header_bar_new());
  g_object_ref_sink(bar);
  // The runner's explicitly packed application icon remains present exactly once.
  auto* image = gtk_image_new_from_icon_name("application-x-executable", GTK_ICON_SIZE_LARGE_TOOLBAR);
  gtk_header_bar_pack_start(bar, image);
  gtk_header_bar_set_show_close_button(bar, TRUE);
  g_object_set_data_full(G_OBJECT(bar), "chrome", cie_window_chrome_new(bar, portal), g_object_unref);
  return bar;
}
static void layout() {
  g_object_set(gtk_settings_get_default(), "gtk-decoration-layout", "icon:minimize,maximize,close", nullptr);
  auto* bar = header(FALSE);
  g_assert_cmpstr(gtk_header_bar_get_decoration_layout(bar), ==, ":minimize,maximize,close");
  g_object_set(gtk_settings_get_default(), "gtk-decoration-layout", "close,icon:minimize,icon,maximize", nullptr);
  g_assert_cmpstr(gtk_header_bar_get_decoration_layout(bar), ==, "close:minimize,maximize");
  g_object_set(gtk_settings_get_default(), "gtk-decoration-layout", "menu:close", nullptr);
  g_assert_cmpstr(gtk_header_bar_get_decoration_layout(bar), ==, "menu:close");
  auto* children = gtk_container_get_children(GTK_CONTAINER(bar));
  g_assert_cmpuint(g_list_length(children), ==, 1);
  g_list_free(children);
  gtk_widget_destroy(GTK_WIDGET(bar));g_object_unref(bar);
}

static GDBusConnection* connection;
static guint scheme = 1;
static void read_setting(GDBusConnection*, const gchar*, const gchar*, const gchar*,
    const gchar* method, GVariant* parameters, GDBusMethodInvocation* invocation, gpointer) {
  const gchar *space, *key;
  g_variant_get(parameters, "(&s&s)", &space, &key);
  g_assert_cmpstr(method, ==, "Read");
  g_assert_cmpstr(space, ==, "org.freedesktop.appearance");
  g_assert_cmpstr(key, ==, "color-scheme");
  g_dbus_method_invocation_return_value(invocation, g_variant_new("(v)", g_variant_new_uint32(scheme)));
}
static void changed(GVariant* value) {
  g_dbus_connection_emit_signal(connection, nullptr, "/org/freedesktop/portal/desktop",
      "org.freedesktop.portal.Settings", "SettingChanged",
      g_variant_new("(ssv)", "org.freedesktop.appearance", "color-scheme", value), nullptr);
}
static void appearance() {
  g_object_set(gtk_settings_get_default(), "gtk-application-prefer-dark-theme", FALSE, nullptr);
  auto* bar = header(TRUE);
  wait_for([] { return dark(); });
  changed(g_variant_new_uint32(2));wait_for([] { return !dark(); });
  changed(g_variant_new_uint32(1));wait_for([] { return dark(); });
  changed(g_variant_new_uint32(0));wait_for([] { return !dark(); });
  gtk_widget_destroy(GTK_WIDGET(bar));g_object_unref(bar);
}
static void close_while_loading() {
  auto* bar = header(TRUE);
  gboolean released = FALSE;
  g_object_weak_ref(G_OBJECT(g_object_get_data(G_OBJECT(bar), "chrome")),
      [](gpointer data, GObject*) { *static_cast<gboolean*>(data) = TRUE; }, &released);
  gtk_widget_destroy(GTK_WIDGET(bar));g_object_unref(bar);
  wait_for([&] { return released; });
}
int main(int argc, char** argv) {
  // Run under dbus-run-session + Xvfb: never replace a desktop's real portal.
  g_test_init(&argc, &argv, nullptr);
  g_setenv("GTK_USE_PORTAL", "0", TRUE);
  g_setenv("NO_AT_BRIDGE", "1", TRUE);
  gtk_init(&argc, &argv);
  connection = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  g_assert_nonnull(connection);
  g_autoptr(GVariant) name = g_dbus_connection_call_sync(connection,
      "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
      g_variant_new("(su)", "org.freedesktop.portal.Desktop", 4u),
      G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, nullptr);
  guint ownership = 0;g_variant_get(name, "(u)", &ownership);
  g_assert_cmpuint(ownership, ==, 1);
  const auto* xml = "<node><interface name='org.freedesktop.portal.Settings'>"
      "<method name='Read'><arg type='s' direction='in'/><arg type='s' direction='in'/>"
      "<arg type='v' direction='out'/></method>"
      "<signal name='SettingChanged'><arg type='s'/><arg type='s'/><arg type='v'/></signal>"
      "</interface></node>";
  g_autoptr(GDBusNodeInfo) info = g_dbus_node_info_new_for_xml(xml, nullptr);
  const GDBusInterfaceVTable table = {read_setting, nullptr, nullptr, {nullptr}};
  const auto registration = g_dbus_connection_register_object(connection,
      "/org/freedesktop/portal/desktop", info->interfaces[0], &table, nullptr, nullptr, nullptr);
  g_assert_cmpuint(registration, >, 0);
  g_test_add_func("/chrome/single-icon-and-desktop-controls", layout);
  g_test_add_func("/chrome/portal-dark-light-default", appearance);
  g_test_add_func("/chrome/close-during-portal-request", close_while_loading);
  const auto result = g_test_run();
  g_dbus_connection_unregister_object(connection, registration);
  g_dbus_connection_close_sync(connection, nullptr, nullptr);g_object_unref(connection);
  return result;
}
