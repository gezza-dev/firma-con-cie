// SPDX-License-Identifier: BSD-3-Clause
#include "text_scaling.h"

#include <cmath>
#include <cstring>

struct _CieTextScaling {
  GObject parent_instance;
  GdkScreen* screen;
  FlMethodChannel* channel;
};

G_DEFINE_TYPE(CieTextScaling, cie_text_scaling, G_TYPE_OBJECT)

static double text_scale(CieTextScaling* self) {
  // GDK's effective font resolution already includes GDK_DPI_SCALE and GTK's
  // backend-specific DPI handling. Do not apply those or the monitor scale
  // again. A missing/invalid resolution uses Flutter's normal 100% fallback.
  const double dpi = gdk_screen_get_resolution(self->screen);
  return std::isfinite(dpi) && dpi > 0 ? dpi / 96.0 : 1.0;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                           gpointer user_data) {
  auto* self = CIE_TEXT_SCALING(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (std::strcmp(fl_method_call_get_name(call), "getTextScale") == 0) {
    g_autoptr(FlValue) value = fl_value_new_float(text_scale(self));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

static void resolution_changed_cb(GObject* screen, GParamSpec* property,
                                   gpointer user_data) {
  auto* self = CIE_TEXT_SCALING(user_data);
  g_autoptr(FlValue) value = fl_value_new_float(text_scale(self));
  fl_method_channel_invoke_method(self->channel, "textScaleChanged", value,
                                  nullptr, nullptr, nullptr);
}

static void cie_text_scaling_dispose(GObject* object) {
  auto* self = CIE_TEXT_SCALING(object);
  if (self->screen != nullptr) {
    g_signal_handlers_disconnect_by_data(self->screen, self);
  }
  if (self->channel != nullptr) {
    fl_method_channel_set_method_call_handler(self->channel, nullptr, nullptr,
                                             nullptr);
  }
  g_clear_object(&self->channel);
  g_clear_object(&self->screen);
  G_OBJECT_CLASS(cie_text_scaling_parent_class)->dispose(object);
}

static void cie_text_scaling_class_init(CieTextScalingClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = cie_text_scaling_dispose;
}

static void cie_text_scaling_init(CieTextScaling* self) {}

CieTextScaling* cie_text_scaling_new(FlBinaryMessenger* messenger,
                                    GdkScreen* screen) {
  auto* self = CIE_TEXT_SCALING(g_object_new(cie_text_scaling_get_type(), nullptr));
  self->screen = GDK_SCREEN(g_object_ref(screen));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(
      messenger, "cie.id/linux_text_scaling", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb, self,
                                           nullptr);
  g_signal_connect(screen, "notify::resolution",
                    G_CALLBACK(resolution_changed_cb), self);
  return self;
}
