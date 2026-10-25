// SPDX-License-Identifier: BSD-3-Clause
#include "window_chrome.h"
#include <cstring>

struct _CieWindowChrome {
  GObject parent_instance;
  GtkHeaderBar* header;  // Cleared by destroy, before the header can be finalized.
  GtkSettings* settings;
  GDBusProxy* portal;
  GCancellable* cancellable;
  gboolean initial_dark;
};
G_DEFINE_TYPE(CieWindowChrome, cie_window_chrome, G_TYPE_OBJECT)

static void update_layout(CieWindowChrome* self) {
  if (!self->header) return;
  g_autofree gchar* layout = nullptr;
  g_object_get(self->settings, "gtk-decoration-layout", &layout, nullptr);
  g_autoptr(GString) filtered = g_string_new(nullptr);
  g_auto(GStrv) sides = g_strsplit(layout ? layout : ":close", ":", 2);
  for (guint i = 0; sides[i]; ++i) {
    if (i) g_string_append_c(filtered, ':');
    g_auto(GStrv) buttons = g_strsplit(sides[i], ",", -1);
    gboolean first = TRUE;
    for (guint j = 0; buttons[j]; ++j) {
      const auto* button = g_strstrip(buttons[j]);
      // The runner already packs its embedded application icon on the left.
      if (!*button || std::strcmp(button, "icon") == 0) continue;
      if (!first) g_string_append_c(filtered, ',');
      g_string_append(filtered, button);
      first = FALSE;
    }
  }
  gtk_header_bar_set_decoration_layout(self->header, filtered->str);
}

static void layout_changed(GObject*, GParamSpec*, CieWindowChrome* self) {
  update_layout(self);
}

static void apply_scheme(CieWindowChrome* self, GVariant* value) {
  if (!self->header || !value) return;
  g_autoptr(GVariant) scheme = g_variant_ref(value);
  while (g_variant_is_of_type(scheme, G_VARIANT_TYPE_VARIANT)) {
    auto* inner = g_variant_get_variant(scheme);
    g_variant_unref(scheme);
    scheme = inner;
  }
  if (!g_variant_is_of_type(scheme, G_VARIANT_TYPE_UINT32)) return;
  const auto preference = g_variant_get_uint32(scheme);
  if (preference > 2) return;
  // Portal: 0 = no preference, 1 = dark, 2 = light. Keep the GTK theme and let
  // it choose its own dark colours; never impose RGB colours or a display scale.
  g_object_set(self->settings, "gtk-application-prefer-dark-theme",
               preference == 0 ? self->initial_dark : preference == 1, nullptr);
}

static void scheme_read(GObject* source, GAsyncResult* result, gpointer data) {
  auto* self = CIE_WINDOW_CHROME(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_proxy_call_finish(G_DBUS_PROXY(source), result, &error);
  if (reply && g_variant_is_of_type(reply, G_VARIANT_TYPE("(v)"))) {
    g_autoptr(GVariant) value = g_variant_get_child_value(reply, 0);
    apply_scheme(self, value);
  }
  g_object_unref(self);
}

static void setting_changed(GDBusProxy*, gchar*, gchar* name, GVariant* parameters,
                            CieWindowChrome* self) {
  if (std::strcmp(name, "SettingChanged") != 0 ||
      !g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ssv)"))) return;
  const gchar *space = nullptr, *key = nullptr;
  g_autoptr(GVariant) value = nullptr;
  g_variant_get(parameters, "(&s&sv)", &space, &key, &value);
  if (std::strcmp(space, "org.freedesktop.appearance") == 0 &&
      std::strcmp(key, "color-scheme") == 0) apply_scheme(self, value);
}

static void portal_ready(GObject*, GAsyncResult* result, gpointer data) {
  auto* self = CIE_WINDOW_CHROME(data);
  g_autoptr(GError) error = nullptr;
  auto* proxy = g_dbus_proxy_new_for_bus_finish(result, &error);
  if (proxy && self->header) {
    self->portal = proxy;
    g_signal_connect_object(proxy, "g-signal", G_CALLBACK(setting_changed), self,
                            static_cast<GConnectFlags>(0));
    g_dbus_proxy_call(proxy, "Read",
        g_variant_new("(ss)", "org.freedesktop.appearance", "color-scheme"),
        G_DBUS_CALL_FLAGS_NONE, 1000, self->cancellable, scheme_read, g_object_ref(self));
  } else if (proxy) {
    g_object_unref(proxy);
  }
  g_object_unref(self);
}

static void header_destroyed(GtkWidget*, CieWindowChrome* self) {
  self->header = nullptr;
  g_cancellable_cancel(self->cancellable);
  g_signal_handlers_disconnect_by_data(self->settings, self);
}

static void cie_window_chrome_dispose(GObject* object) {
  auto* self = CIE_WINDOW_CHROME(object);
  if (self->settings) g_signal_handlers_disconnect_by_data(self->settings, self);
  g_clear_object(&self->portal);
  g_clear_object(&self->settings);
  g_clear_object(&self->cancellable);
  G_OBJECT_CLASS(cie_window_chrome_parent_class)->dispose(object);
}

static void cie_window_chrome_class_init(CieWindowChromeClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = cie_window_chrome_dispose;
}
static void cie_window_chrome_init(CieWindowChrome*) {}

CieWindowChrome* cie_window_chrome_new(GtkHeaderBar* header, gboolean use_portal) {
  auto* self = CIE_WINDOW_CHROME(g_object_new(cie_window_chrome_get_type(), nullptr));
  self->header = header;
  self->settings = GTK_SETTINGS(g_object_ref(gtk_widget_get_settings(GTK_WIDGET(header))));
  self->cancellable = g_cancellable_new();
  g_object_get(self->settings, "gtk-application-prefer-dark-theme", &self->initial_dark, nullptr);
  g_signal_connect_object(header, "destroy", G_CALLBACK(header_destroyed), self,
                          static_cast<GConnectFlags>(0));
  g_signal_connect_object(self->settings, "notify::gtk-decoration-layout",
                          G_CALLBACK(layout_changed), self, static_cast<GConnectFlags>(0));
  update_layout(self);
  if (use_portal) {
    g_dbus_proxy_new_for_bus(G_BUS_TYPE_SESSION, G_DBUS_PROXY_FLAGS_DO_NOT_LOAD_PROPERTIES,
        nullptr, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Settings", self->cancellable, portal_ready, g_object_ref(self));
  }
  return self;
}
