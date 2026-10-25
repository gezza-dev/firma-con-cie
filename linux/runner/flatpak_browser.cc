// SPDX-License-Identifier: BSD-3-Clause
#include "flatpak_browser.h"
#include <cstring>

struct State { GDBusConnection* bus; GCancellable* cancel; FlMethodChannel* channel; };
static void respond(FlMethodCall* call, const gchar* json) {
  g_autoptr(FlValue) value = fl_value_new_string(json);
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  fl_method_call_respond(call, response, nullptr);
}
static void finished(GObject* source, GAsyncResult* result, gpointer data) {
  auto* call = FL_METHOD_CALL(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, &error);
  if (reply) {
    const gchar* json = nullptr;g_variant_get(reply, "(&s)", &json);
    respond(call, json);
  } else {
    const bool missing = error && (g_error_matches(error, G_DBUS_ERROR, G_DBUS_ERROR_SERVICE_UNKNOWN) ||
        g_error_matches(error, G_DBUS_ERROR, G_DBUS_ERROR_NAME_HAS_NO_OWNER));
    respond(call, missing ? "{\"ok\":false,\"code\":\"helper_missing\"}" :
                           "{\"ok\":false,\"code\":\"helper_unavailable\"}");
  }
  g_object_unref(call);
}
static void request(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* self = static_cast<State*>(data);
  auto* args = fl_method_call_get_args(call);
  if (std::strcmp(fl_method_call_get_name(call), "request") != 0 ||
      !args || fl_value_get_type(args) != FL_VALUE_TYPE_STRING) {
    respond(call, "{\"ok\":false,\"code\":\"invalid_request\"}");return;
  }
  const auto* json = fl_value_get_string(args);
  if (std::strlen(json) > 5*1024*1024 || !self->bus) {
    respond(call, "{\"ok\":false,\"code\":\"helper_unavailable\"}");return;
  }
  g_dbus_connection_call(self->bus, "it.giancarloezza.FirmaConCIE.BrowserHelper1",
      "/it/giancarloezza/FirmaConCIE/BrowserHelper1", "it.giancarloezza.FirmaConCIE.BrowserHelper1",
      "Request", g_variant_new("(s)", json), G_VARIANT_TYPE("(s)"),
      G_DBUS_CALL_FLAGS_NONE, 65000, self->cancel, finished, g_object_ref(call));
}
GObject* cie_flatpak_browser_new(FlBinaryMessenger* messenger, GDBusConnection* bus) {
  auto* owner = G_OBJECT(g_object_new(G_TYPE_OBJECT, nullptr));
  auto* state = new State{bus ? G_DBUS_CONNECTION(g_object_ref(bus)) : nullptr, g_cancellable_new(), nullptr};
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  state->channel = fl_method_channel_new(messenger, "cie.id/flatpak_browser_setup", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(state->channel, request, state, nullptr);
  g_object_set_data_full(owner, "state", state, [](gpointer data) {
    auto* state = static_cast<State*>(data);
    g_cancellable_cancel(state->cancel);
    fl_method_channel_set_method_call_handler(state->channel, nullptr, nullptr, nullptr);
    g_clear_object(&state->channel);g_clear_object(&state->bus);g_clear_object(&state->cancel);
    delete state;
  });
  return owner;
}
