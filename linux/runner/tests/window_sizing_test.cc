// SPDX-License-Identifier: BSD-3-Clause
#include "window_sizing.h"

#include <climits>
#include <cstring>
#include <initializer_list>

static void large_desktop() {
  const auto size = cie_window_size_for_area(1920, 1040, 48);
  g_assert_cmpint(size.width, ==, 1280);
  g_assert_cmpint(size.height, ==, 720);
  g_assert_false(size.maximize);
}

static void small_desktop() {
  // 1280x720 monitor with a panel: the titlebar must fit as well as Flutter.
  const auto size = cie_window_size_for_area(1280, 688, 48);
  g_assert_true(size.maximize);
  g_assert_cmpint(size.width, ==, 1256);
  g_assert_cmpint(size.height, ==, 616);
  g_assert_cmpint(size.height + 48, <, 688);
  // A 4K display at 200% reports logical 1920x1080 to GDK, not 3840x2160.
  const auto hidpi = cie_window_size_for_area(1920, 1080, 48);
  g_assert_cmpint(hidpi.width, ==, 1280);
  g_assert_cmpint(hidpi.height, ==, 720);
  g_assert_false(hidpi.maximize);
  const auto scaled_small = cie_window_size_for_area(960, 540, 48);
  g_assert_true(scaled_small.maximize);
  g_assert_cmpint(scaled_small.width, ==, 936);
  g_assert_cmpint(scaled_small.height, ==, 468);
}

static void invalid_or_tiny_area() {
  for (const auto width : {-1, 0}) {
    const auto size = cie_window_size_for_area(width, 600, 48);
    g_assert_cmpint(size.width, ==, 1280);
    g_assert_cmpint(size.height, ==, 720);
    g_assert_false(size.maximize);
  }
  const auto size = cie_window_size_for_area(1, 1, INT_MAX);
  g_assert_cmpint(size.width, ==, 1);
  g_assert_cmpint(size.height, ==, 1);
  g_assert_true(size.maximize);
}

static void area_changes() {
  // Includes workareas for 100/125/150/200% display scaling, and tall titlebars
  // from larger fonts. These already-scaled inputs are never multiplied again.
  for (const auto width : {640, 800, 1024, 1280, 1536, 1920, INT_MAX})
    for (const auto height : {400, 480, 576, 720, 864, 1080, INT_MAX})
      for (const auto titlebar : {0, 40, 64, 96}) {
        const auto size = cie_window_size_for_area(width, height, titlebar);
        g_assert_cmpint(size.width, >, 0);
        g_assert_cmpint(size.height, >, 0);
        g_assert_cmpint(size.width, <=, 1280);
        g_assert_cmpint(size.height, <=, 720);
        g_assert_cmpint(size.width + 24, <=, width);
        g_assert_cmpint(size.height + titlebar + 24, <=, height);
      }
}

int main(int argc, char** argv) {
  if (argc == 2 && std::strcmp(argv[1], "--desktop-read-only") == 0) {
    // Query logical monitor metadata only: no application or GTK window.
    if (!gtk_init_check(&argc, &argv)) return 1;
    auto* display = gdk_display_get_default();
    g_print("{\"monitors\":[");
    for (int i = 0; i < gdk_display_get_n_monitors(display); ++i) {
      auto* monitor = gdk_display_get_monitor(display, i);
      GdkRectangle geometry{}, workarea{};
      gdk_monitor_get_geometry(monitor, &geometry);
      gdk_monitor_get_workarea(monitor, &workarea);
      g_print("%s{\"logicalWidth\":%d,\"logicalHeight\":%d,"
              "\"workareaWidth\":%d,\"workareaHeight\":%d,\"displayScale\":%d}",
              i ? "," : "", geometry.width, geometry.height,
              workarea.width, workarea.height, gdk_monitor_get_scale_factor(monitor));
    }
    g_print("]}\n");
    return 0;
  }
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/window/large-desktop", large_desktop);
  g_test_add_func("/window/small-and-scaled-desktop", small_desktop);
  g_test_add_func("/window/invalid-or-tiny", invalid_or_tiny_area);
  g_test_add_func("/window/workarea-changes", area_changes);
  return g_test_run();
}
