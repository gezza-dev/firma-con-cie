// SPDX-License-Identifier: BSD-3-Clause
#include "window_sizing.h"

#include <algorithm>
#include <cstdint>

namespace {
constexpr int preferred_width = 1280;
constexpr int preferred_height = 720;
constexpr int edge_space = 24;
constexpr const char* state_key = "cie-window-sizing";

struct State {
  bool initialized = false;
  GdkRectangle area{};
  int titlebar_height = -1;
};

void refresh(GtkWindow* window) {
  auto* state = static_cast<State*>(g_object_get_data(G_OBJECT(window), state_key));
  if (!state || gtk_widget_in_destruction(GTK_WIDGET(window))) return;
  auto* display = gtk_widget_get_display(GTK_WIDGET(window));
  if (!display) return;
  GdkMonitor* monitor = nullptr;
  if (auto* surface = gtk_widget_get_window(GTK_WIDGET(window)))
    monitor = gdk_display_get_monitor_at_window(display, surface);
  if (!monitor) monitor = gdk_display_get_primary_monitor(display);
  if (!monitor && gdk_display_get_n_monitors(display) > 0)
    monitor = gdk_display_get_monitor(display, 0);
  if (!monitor) return;  // Keep the preferred size until a monitor is available.

  GdkRectangle area{};
  gdk_monitor_get_workarea(monitor, &area);
  if (area.width <= 0 || area.height <= 0) return;
  int titlebar_height = 40;  // Server decoration allowance on X11.
  if (auto* titlebar = gtk_window_get_titlebar(window)) {
    int minimum = 0;
    gtk_widget_get_preferred_height(titlebar, &minimum, &titlebar_height);
  }
  if (state->initialized && state->area.x == area.x && state->area.y == area.y &&
      state->area.width == area.width && state->area.height == area.height &&
      state->titlebar_height == titlebar_height) return;

  const auto size = cie_window_size_for_area(area.width, area.height, titlebar_height);
  GdkGeometry hints{};
  // These minima must shrink too: a fixed minimum can defeat compositor fitting.
  hints.min_width = std::min(640, size.available_width);
  hints.min_height = std::min(400, size.available_height);
  gtk_window_set_geometry_hints(window, nullptr, &hints, GDK_HINT_MIN_SIZE);
  if (!state->initialized) {
    gtk_window_set_default_size(window, size.width, size.height);
    if (size.maximize) gtk_window_maximize(window);
  } else if (!gtk_window_is_maximized(window)) {
    int width = 0, height = 0;
    gtk_window_get_size(window, &width, &height);
    // Preserve a user's smaller window. Maximize an oversized one after a
    // display change, letting GNOME/KDE reserve their actual panels on Wayland
    // (where GDK may expose only the whole monitor geometry as the workarea).
    if (width > size.available_width || height > size.available_height)
      gtk_window_maximize(window);
  }
  state->area = area;
  state->titlebar_height = titlebar_height;
  state->initialized = true;
}

void monitor_changed(GObject*, GParamSpec*, GtkWindow* window) { refresh(window); }

void watch_monitor(GdkDisplay*, GdkMonitor* monitor, GtkWindow* window) {
  for (const auto* signal : {"notify::workarea", "notify::geometry", "notify::scale-factor"})
    g_signal_connect_object(monitor, signal, G_CALLBACK(monitor_changed), window,
                            G_CONNECT_DEFAULT);
  refresh(window);
}

void monitor_removed(GdkDisplay*, GdkMonitor*, GtkWindow* window) { refresh(window); }

gboolean configured(GtkWidget* window, GdkEventConfigure*, gpointer) {
  refresh(GTK_WINDOW(window));
  return FALSE;
}
}  // namespace

CieWindowSize cie_window_size_for_area(int width, int height, int titlebar_height) {
  if (width <= 0 || height <= 0)
    return {preferred_width, preferred_height, preferred_width, preferred_height, false};
  const int available_width = std::max(1, width - edge_space);
  const int available_height = static_cast<int>(std::max<int64_t>(
      1, int64_t{height} - std::max(0, titlebar_height) - edge_space));
  return {std::min(preferred_width, available_width),
          std::min(preferred_height, available_height), available_width, available_height,
          preferred_width > available_width || preferred_height > available_height};
}

void cie_window_sizing_attach(GtkWindow* window) {
  g_return_if_fail(GTK_IS_WINDOW(window));
  g_return_if_fail(!g_object_get_data(G_OBJECT(window), state_key));
  g_object_set_data_full(G_OBJECT(window), state_key, new State,
                        [](gpointer state) { delete static_cast<State*>(state); });
  gtk_window_set_resizable(window, TRUE);
  gtk_window_set_default_size(window, preferred_width, preferred_height);
  // GTK uses the monitor workarea for initial centering, including panels.
  // This is an initial hint, not CENTER_ALWAYS: subsequent user moves stay free.
  // Wayland/compositors retain final authority over top-level placement.
  gtk_window_set_position(window, GTK_WIN_POS_CENTER);
  g_signal_connect(window, "configure-event", G_CALLBACK(configured), nullptr);
  auto* display = gtk_widget_get_display(GTK_WIDGET(window));
  if (!display) return;
  g_signal_connect_object(display, "monitor-added", G_CALLBACK(watch_monitor), window,
                          G_CONNECT_DEFAULT);
  g_signal_connect_object(display, "monitor-removed", G_CALLBACK(monitor_removed), window,
                          G_CONNECT_DEFAULT);
  for (int i = 0; i < gdk_display_get_n_monitors(display); ++i)
    watch_monitor(display, gdk_display_get_monitor(display, i), window);
  refresh(window);
}
