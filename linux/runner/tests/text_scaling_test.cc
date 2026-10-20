// SPDX-License-Identifier: BSD-3-Clause
#include "text_scaling.h"

#include <cstring>
#include <initializer_list>

// A screen with only GDK's real resolution property: no display, window, Flutter
// engine, native CIE library, or hardware connection is started by these tests.
static GType test_screen_get_type() {
  static const GType type = [] {
    GTypeQuery query;
    g_type_query(GDK_TYPE_SCREEN, &query);
    return g_type_register_static_simple(GDK_TYPE_SCREEN, "CieTestScreen",
        query.class_size, nullptr, query.instance_size, nullptr,
        static_cast<GTypeFlags>(0));
  }();
  return type;
}

struct TestMessenger {
  GObject parent;
  FlBinaryMessengerMessageHandler handler;
  gpointer handler_data;
  GDestroyNotify handler_destroy;
  GBytes* response;
  double last_scale;
  unsigned notifications;
};
struct TestMessengerClass { GObjectClass parent; };
static void messenger_iface_init(FlBinaryMessengerInterface* iface);
G_DEFINE_TYPE_WITH_CODE(TestMessenger, test_messenger, G_TYPE_OBJECT,
                       G_IMPLEMENT_INTERFACE(fl_binary_messenger_get_type(),
                                             messenger_iface_init))
static void test_messenger_init(TestMessenger* self) {}
static void test_messenger_class_init(TestMessengerClass* klass) {}

static void set_handler(FlBinaryMessenger* messenger, const gchar* name,
                        FlBinaryMessengerMessageHandler handler, gpointer data,
                        GDestroyNotify destroy) {
  auto* self = reinterpret_cast<TestMessenger*>(messenger);
  g_assert_cmpstr(name, ==, "cie.id/linux_text_scaling");
  if (self->handler_destroy) self->handler_destroy(self->handler_data);
  self->handler = handler;
  self->handler_data = data;
  self->handler_destroy = destroy;
}
static gboolean send_response(FlBinaryMessenger* messenger,
                               FlBinaryMessengerResponseHandle* handle,
                               GBytes* response, GError** error) {
  auto* self = reinterpret_cast<TestMessenger*>(messenger);
  g_clear_pointer(&self->response, g_bytes_unref);
  self->response = g_bytes_ref(response);
  return TRUE;
}
static void send_on_channel(FlBinaryMessenger* messenger, const gchar* name,
                             GBytes* message, GCancellable* cancellable,
                             GAsyncReadyCallback callback, gpointer data) {
  auto* self = reinterpret_cast<TestMessenger*>(messenger);
  g_assert_cmpstr(name, ==, "cie.id/linux_text_scaling");
  g_autoptr(FlStandardMessageCodec) codec = fl_standard_message_codec_new();
  size_t offset = 0;
  g_autoptr(FlValue) method = fl_standard_message_codec_read_value(codec, message, &offset, nullptr);
  g_autoptr(FlValue) args = fl_standard_message_codec_read_value(codec, message, &offset, nullptr);
  g_assert_cmpstr(fl_value_get_string(method), ==, "textScaleChanged");
  self->last_scale = fl_value_get_float(args);
  self->notifications++;
}
static void messenger_iface_init(FlBinaryMessengerInterface* iface) {
  iface->set_message_handler_on_channel = set_handler;
  iface->send_response = send_response;
  iface->send_on_channel = send_on_channel;
}

struct Fixture {
  TestMessenger* messenger = reinterpret_cast<TestMessenger*>(
      g_object_new(test_messenger_get_type(), nullptr));
  GdkScreen* screen = GDK_SCREEN(g_object_new(test_screen_get_type(), nullptr));
  CieTextScaling* scaling = cie_text_scaling_new(FL_BINARY_MESSENGER(messenger), screen);
  ~Fixture() {
    g_clear_object(&scaling);
    set_handler(FL_BINARY_MESSENGER(messenger), "cie.id/linux_text_scaling",
                nullptr, nullptr, nullptr);
    g_clear_pointer(&messenger->response, g_bytes_unref);
    g_object_unref(messenger);
    g_object_unref(screen);
  }
  void call(const char* method) {
    g_autoptr(FlStandardMessageCodec) codec = fl_standard_message_codec_new();
    g_autoptr(GByteArray) buffer = g_byte_array_new();
    g_autoptr(FlValue) name = fl_value_new_string(method);
    g_assert_true(fl_standard_message_codec_write_value(codec, buffer, name, nullptr));
    g_assert_true(fl_standard_message_codec_write_value(codec, buffer, nullptr, nullptr));
    g_autoptr(GBytes) message = g_byte_array_free_to_bytes(g_steal_pointer(&buffer));
    g_autoptr(FlBinaryMessengerResponseHandle) handle =
        FL_BINARY_MESSENGER_RESPONSE_HANDLE(g_object_new(
            fl_binary_messenger_response_handle_get_type(), nullptr));
    messenger->handler(FL_BINARY_MESSENGER(messenger), "cie.id/linux_text_scaling",
                        message, handle, messenger->handler_data);
  }
  double get_scale() {
    call("getTextScale");
    gsize length = 0;
    const auto* bytes = static_cast<const guint8*>(g_bytes_get_data(messenger->response, &length));
    g_assert_cmpuint(length, >, 1);
    g_assert_cmpint(bytes[0], ==, 0); // StandardMethodCodec success envelope.
    size_t offset = 1;
    g_autoptr(FlStandardMessageCodec) codec = fl_standard_message_codec_new();
    g_autoptr(FlValue) result = fl_standard_message_codec_read_value(codec, messenger->response, &offset, nullptr);
    return fl_value_get_float(result);
  }
};

static void dpi_values() {
  Fixture f;
  // Effective font DPI is already compensated by GDK. 192 DPI at GDK_SCALE=2
  // and GDK_DPI_SCALE=.5 therefore arrives here as 96, not as 192.
  for (double dpi : {76.8, 96.0, 120.0, 144.0, 192.0, -1.0}) {
    gdk_screen_set_resolution(f.screen, dpi);
    g_assert_cmpfloat_with_epsilon(f.get_scale(), dpi > 0 ? dpi / 96 : 1, 1e-9);
  }
}
static void changes_and_disposal() {
  Fixture f;
  gdk_screen_set_resolution(f.screen, 120);
  g_assert_cmpuint(f.messenger->notifications, ==, 1);
  g_assert_cmpfloat(f.messenger->last_scale, ==, 1.25);
  gdk_screen_set_resolution(f.screen, 144);
  g_assert_cmpuint(f.messenger->notifications, ==, 2);
  g_assert_cmpfloat(f.messenger->last_scale, ==, 1.5);
  gdk_screen_set_resolution(f.screen, 96);
  g_assert_cmpfloat(f.messenger->last_scale, ==, 1);
  const unsigned count = f.messenger->notifications;
  g_clear_object(&f.scaling);
  gdk_screen_set_resolution(f.screen, 120);
  g_assert_cmpuint(f.messenger->notifications, ==, count);
}
static void unsupported_method() {
  Fixture f;
  f.call("unknown");
  g_assert_cmpuint(g_bytes_get_size(f.messenger->response), ==, 0);
}

int main(int argc, char** argv) {
  if (argc == 2 && std::strcmp(argv[1], "--desktop-read-only") == 0) {
    if (!gtk_init_check(&argc, &argv)) return 1;
    // Initialize GTK's effective settings without creating any window.
    GtkSettings* settings = gtk_settings_get_default();
    gint raw_dpi = -1;
    g_object_get(settings, "gtk-xft-dpi", &raw_dpi, nullptr);
    Fixture f;
    g_clear_object(&f.scaling);
    g_set_object(&f.screen, gdk_screen_get_default());
    f.scaling = cie_text_scaling_new(FL_BINARY_MESSENGER(f.messenger), f.screen);
    g_print("{\"gtkDpi\":%.3f,\"effectiveFontDpi\":%.3f,\"channelScale\":%.3f}\n",
            raw_dpi / 1024.0, gdk_screen_get_resolution(f.screen), f.get_scale());
    return 0;
  }
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/text-scaling/dpi-values", dpi_values);
  g_test_add_func("/text-scaling/changes-and-disposal", changes_and_disposal);
  g_test_add_func("/text-scaling/unsupported-method", unsupported_method);
  return g_test_run();
}
