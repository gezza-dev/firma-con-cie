// SPDX-License-Identifier: BSD-3-Clause
// Exercises the production host window with a child that pumps nested native
// resize messages, as Flutter does while waiting for its render surface.
#include "win32_window.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cwchar>

namespace {
int checks = 0;
void Require(bool condition, const char* message) {
  ++checks;
  if (!condition) {
    std::fprintf(stderr, "FAIL: %s\n", message);
    std::exit(1);
  }
}
void Pump() {
  MSG msg{};
  int count = 0;
  while (PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
    Require(++count < 500, "native queue drains without a resize spin");
    TranslateMessage(&msg);
    DispatchMessage(&msg);
  }
}
struct Probe {
  HWND parent = nullptr;
  int depth = 0;
  int max_depth = 0;
  int size_events = 0;
  bool nested = false;
  bool injected = false;
};
LRESULT CALLBACK ChildProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
  if (msg == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCT*>(lp);
    SetWindowLongPtr(h, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  auto* probe = reinterpret_cast<Probe*>(GetWindowLongPtr(h, GWLP_USERDATA));
  if (msg == WM_SIZE && probe) {
    ++probe->depth;
    ++probe->size_events;
    probe->max_depth = std::max(probe->max_depth, probe->depth);
    if (probe->nested && !probe->injected) {
      probe->injected = true;
      for (int i = 0; i < 50; ++i) {
        SetWindowPos(probe->parent, nullptr, 10, 10, 1000 + i, 700 + i,
                     SWP_NOZORDER | SWP_NOACTIVATE);
      }
      // The child can pump messages inside its size callback. Deferred work
      // must not be posted until that callback has returned.
      Pump();
    }
    --probe->depth;
  }
  return DefWindowProc(h, msg, wp, lp);
}
void CheckChild(Win32Window& host, HWND child) {
  const HWND parent = host.GetHandle();
  RECT expected = host.GetClientArea(), actual{};
  Require(expected.bottom > expected.top, "read host content area below caption");
  Require(GetWindowRect(child, &actual) != FALSE, "read child bounds");
  MapWindowPoints(nullptr, parent, reinterpret_cast<POINT*>(&actual), 2);
  Require(EqualRect(&actual, &expected) != FALSE, "child fills the latest host client area");
}
}  // namespace

int main() {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  Win32Window host;
  Require(host.Create(L"CIE synthetic resize regression", {0, 0}, {900, 600}, true),
          "create production host window");
  RECT initial{};
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  Require(GetWindowRect(host.GetHandle(), &initial) != FALSE,
          "read initial decorated window frame");
  Require(GetMonitorInfo(MonitorFromWindow(host.GetHandle(), MONITOR_DEFAULTTONEAREST),
                         &monitor) != FALSE, "read real monitor workarea");
  Require(std::abs((initial.left + initial.right) -
                   (monitor.rcWork.left + monitor.rcWork.right)) <= 1 &&
          std::abs((initial.top + initial.bottom) -
                   (monitor.rcWork.top + monitor.rcWork.bottom)) <= 1,
          "startup frame is centered in the actual workarea within one pixel");
  Require(initial.left >= monitor.rcWork.left && initial.top >= monitor.rcWork.top &&
          initial.right <= monitor.rcWork.right && initial.bottom <= monitor.rcWork.bottom,
          "startup frame does not cover reserved taskbar space");
  wchar_t title[128]{};
  GetWindowText(host.GetHandle(), title, 128);
  Require(std::wcscmp(title, L"CIE synthetic resize regression") == 0,
          "native window title remains available to accessibility and taskbar");
  const auto content = host.GetClientArea();
  if (content.top > 0) {
    POINT caption_point{content.right / 2, content.top / 2};
    ClientToScreen(host.GetHandle(), &caption_point);
    Require(SendMessage(host.GetHandle(), WM_NCHITTEST, 0,
                        MAKELPARAM(caption_point.x, caption_point.y)) == HTCAPTION,
            "centered title stays a native drag/double-click area");
    Require(SendMessage(host.GetHandle(), WM_NCHITTEST, 0,
                        MAKELPARAM((initial.left + initial.right) / 2,
                                   initial.top + 1)) == HTTOP,
            "top border remains natively resizable");
    POINT icon_point{10, content.top / 2};
    ClientToScreen(host.GetHandle(), &icon_point);
    Require(SendMessage(host.GetHandle(), WM_NCHITTEST, 0,
                        MAKELPARAM(icon_point.x, icon_point.y)) == HTSYSMENU,
            "app icon preserves the native system menu");
  }
  const LONG_PTR style = GetWindowLongPtr(host.GetHandle(), GWL_STYLE);
  Require((style & (WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX |
                    WS_THICKFRAME)) == WS_OVERLAPPEDWINDOW,
          "native caption/buttons/resize styles are preserved");
  Probe probe;
  probe.parent = host.GetHandle();
  WNDCLASS wc{};
  wc.lpfnWndProc = ChildProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = L"CIE_RESIZE_SYNTHETIC_CHILD";
  Require(RegisterClass(&wc) != 0, "register synthetic child");
  HWND child = CreateWindow(wc.lpszClassName, L"", WS_CHILD, 0, 0, 10, 10,
                            probe.parent, nullptr, wc.hInstance, &probe);
  Require(child != nullptr, "create synthetic child");
  host.SetChildContent(child);
  Pump();
  CheckChild(host, child);

  probe.size_events = probe.max_depth = 0;
  probe.nested = true;
  SetWindowPos(probe.parent, nullptr, 10, 10, 1100, 800,
               SWP_NOZORDER | SWP_NOACTIVATE);
  Pump();
  Require(probe.injected, "nested resize messages were exercised");
  Require(probe.max_depth == 1, "child resize callback is never re-entered");
  Require(probe.size_events == 2, "50 nested sizes coalesce to the latest size");
  CheckChild(host, child);

  const int before = probe.size_events;
  SendMessage(probe.parent, WM_SIZE, SIZE_RESTORED, 0);
  Pump();
  Require(probe.size_events == before, "unchanged geometry does not recreate the surface");
  SendMessage(probe.parent, WM_SIZE, SIZE_MINIMIZED, 0);
  Require(probe.size_events == before, "minimization does not create a zero-size surface");

  for (int i = 0; i < 300; ++i) {
    const int delta = (i % 2 ? 299 - i : i) % 280;
    SetWindowPos(probe.parent, nullptr, 10, 10, 850 + delta * 2, 550 + delta,
                 SWP_NOZORDER | SWP_NOACTIVATE);
    Pump();
    CheckChild(host, child);
  }
  Require(probe.max_depth == 1, "repeated shrinking and growing stays non-recursive");
  RECT moved{};
  Require(GetWindowRect(probe.parent, &moved) != FALSE, "read manually moved frame");
  Require(moved.left == 10 && moved.top == 10,
          "later moves and resize cycles do not recenter the window");
  Require(!IsWindowVisible(probe.parent), "test window was never shown");
  host.Destroy();
  Pump();
  UnregisterClass(wc.lpszClassName, wc.hInstance);
  std::printf("PASS: %d checks, nested resize coalescing and 300 grow/shrink cycles.\n", checks);
  return 0;
}
