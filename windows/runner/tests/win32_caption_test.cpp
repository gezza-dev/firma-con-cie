// SPDX-License-Identifier: BSD-3-Clause
// Real DWM layout/hit testing, without a CIE, Flutter engine or input injection.
#include "win32_window.h"
#include <dwmapi.h>
#include <cstdio>
#include <cstdlib>

namespace {
int failures = 0, checks = 0;
void Require(bool ok, const char* message) {
  ++checks;
  if (!ok) { ++failures; std::fprintf(stderr, "FAIL: %s\n", message); }
}
void Pump() {
  MSG message{};
  while (PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
    TranslateMessage(&message);
    DispatchMessage(&message);
  }
  DwmFlush();
}
void CheckButtons(HWND window, const char* state) {
  TITLEBARINFOEX title{};
  title.cbSize = sizeof(title);
  SendMessage(window, WM_GETTITLEBARINFOEX, 0, reinterpret_cast<LPARAM>(&title));
  for (int index : {2, 3, 5}) {
    const RECT rect = title.rgrect[index];
    const LRESULT expected = index == 2 ? HTMINBUTTON : index == 3 ? HTMAXBUTTON : HTCLOSE;
    Require(rect.right > rect.left && rect.bottom > rect.top, "OS provides button bounds");
    for (const POINT fraction : {POINT{2, 2}, POINT{1, 1}, POINT{3, 1},
                                POINT{1, 3}, POINT{3, 3}}) {
      const auto hit = SendMessage(window, WM_NCHITTEST, 0,
          MAKELPARAM(rect.left + (rect.right - rect.left) * fraction.x / 4,
                     rect.top + (rect.bottom - rect.top) * fraction.y / 4));
      std::printf("%s index=%d point=%ld/4,%ld/4 hit=%lld expected=%lld\n",
          state, index, fraction.x, fraction.y,
          static_cast<long long>(hit), static_cast<long long>(expected));
      Require(hit == expected, "visible caption button maps to its native hit code");
    }
    // Exercise the production non-client hover/leave route without moving the
    // real mouse or invoking a system command. Repainting must cover both edges.
    ValidateRect(window, nullptr);
    SendMessage(window, WM_NCMOUSEMOVE, expected,
                MAKELPARAM((rect.left + rect.right) / 2,
                           (rect.top + rect.bottom) / 2));
    Require(GetUpdateRect(window, nullptr, FALSE) != FALSE,
            "entering each native button invalidates its visual hover");
    ValidateRect(window, nullptr);
    SendMessage(window, WM_NCMOUSELEAVE, 0, 0);
    Require(GetUpdateRect(window, nullptr, FALSE) != FALSE,
            "leaving each native button invalidates its visual hover");
    ValidateRect(window, nullptr);
  }
}
}
int main() {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  Win32Window host;
  if (!host.Create(L"CIE caption regression (no card)", {0, 0}, {900, 600}, true)) return 1;
  HWND window = host.GetHandle();
  SetWindowLongPtr(window, GWL_EXSTYLE, GetWindowLongPtr(window, GWL_EXSTYLE) |
                   WS_EX_NOACTIVATE);
  for (int cycle = 0; cycle < 2; ++cycle) {
    ShowWindow(window, SW_RESTORE);
    SetWindowPos(window, HWND_BOTTOM, 100, 100, 900, 600, SWP_NOACTIVATE);
    Pump();
    Require(!IsZoomed(window), "normal-state test really uses a restored frame");
    CheckButtons(window, "normal");
    ShowWindow(window, SW_SHOWMAXIMIZED);
    SetWindowPos(window, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    Pump();
    Require(IsZoomed(window), "maximized-state test really uses a maximized frame");
    CheckButtons(window, "maximized");
    ShowWindow(window, SW_MINIMIZE);
    Pump();
    ShowWindow(window, SW_RESTORE);
    Pump();
    Require(IsZoomed(window), "restoring a minimized maximized frame stays maximized");
    CheckButtons(window, "restored-from-minimize");
    ShowWindow(window, SW_HIDE);
  }
  host.Destroy();
  std::printf("Caption hit tests: %d checks, %d failures.\n", checks, failures);
  return failures ? 1 : 0;
}
