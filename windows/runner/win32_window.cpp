#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include <algorithm>

#include "../../native/desktop/window_geometry.h"

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr UINT kResizeChildContent = WM_APP + 0x43;

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Convert logical preferences to physical pixels exactly once.
int Scale(int source, UINT dpi) {
  return static_cast<int>(cie_window_scale_96(source, dpi));
}

RECT FitToMonitorWorkArea(const RECT& proposed, HMONITOR monitor) {
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfo(monitor, &info)) return proposed;
  const auto fitted = cie_window_fit_rect(
      {double(proposed.left), double(proposed.top),
       double(proposed.right) - proposed.left, double(proposed.bottom) - proposed.top},
      {double(info.rcWork.left), double(info.rcWork.top),
       double(info.rcWork.right) - info.rcWork.left,
       double(info.rcWork.bottom) - info.rcWork.top});
  return {static_cast<LONG>(fitted.x), static_cast<LONG>(fitted.y),
          static_cast<LONG>(fitted.x + fitted.width),
          static_cast<LONG>(fitted.y + fitted.height)};
}

// Convert only a logical minimum client size; include DPI-aware non-client
// decorations. Suggested WM_DPICHANGED rectangles never use this conversion.
RECT MinimumWindowRect(HWND window, UINT dpi) {
  RECT rect{0, 0, Scale(640, dpi), Scale(400, dpi)};
  const auto style = static_cast<DWORD>(GetWindowLongPtr(window, GWL_STYLE));
  const auto extended = static_cast<DWORD>(GetWindowLongPtr(window, GWL_EXSTYLE));
  using AdjustForDpi = BOOL(WINAPI*)(LPRECT, DWORD, BOOL, DWORD, UINT);
  const auto adjust = reinterpret_cast<AdjustForDpi>(
      GetProcAddress(GetModuleHandleW(L"user32.dll"), "AdjustWindowRectExForDpi"));
  if (adjust) {
    adjust(&rect, style, FALSE, extended, dpi);
  } else {
    AdjustWindowRectEx(&rect, style, FALSE, extended);
  }
  return rect;
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  current_dpi_ = FlutterDesktopGetDpiForMonitor(monitor);
  if (!current_dpi_) current_dpi_ = 96;
  const RECT requested{Scale(origin.x, current_dpi_), Scale(origin.y, current_dpi_),
                       Scale(origin.x, current_dpi_) + Scale(size.width, current_dpi_),
                       Scale(origin.y, current_dpi_) + Scale(size.height, current_dpi_)};
  const RECT fitted = FitToMonitorWorkArea(requested, monitor);
  start_maximized_ = fitted.right - fitted.left < requested.right - requested.left ||
                     fitted.bottom - fitted.top < requested.bottom - requested.top;

  HWND window = CreateWindow(
      window_class, title.c_str(),
      WS_OVERLAPPEDWINDOW,
      fitted.left, fitted.top, fitted.right - fitted.left, fitted.bottom - fitted.top,
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, start_maximized_ ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_GETMINMAXINFO: {
      DefWindowProc(hwnd, message, wparam, lparam);
      MONITORINFO monitor{};
      monitor.cbSize = sizeof(monitor);
      if (GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &monitor)) {
        auto* limits = reinterpret_cast<MINMAXINFO*>(lparam);
        const auto minimum = MinimumWindowRect(hwnd, current_dpi_);
        limits->ptMinTrackSize.x = std::min(minimum.right - minimum.left,
                                           monitor.rcWork.right - monitor.rcWork.left);
        limits->ptMinTrackSize.y = std::min(minimum.bottom - minimum.top,
                                           monitor.rcWork.bottom - monitor.rcWork.top);
      }
      // Preserve Windows' own maximized frame/border calculation and taskbar.
      return 0;
    }

    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      current_dpi_ = LOWORD(wparam) ? LOWORD(wparam) : 96;
      const auto* suggested = reinterpret_cast<RECT*>(lparam);
      // These coordinates are already physical pixels at the new DPI.
      const auto fitted = FitToMonitorWorkArea(
          *suggested, MonitorFromRect(suggested, MONITOR_DEFAULTTONEAREST));
      SetWindowPos(hwnd, nullptr, fitted.left, fitted.top, fitted.right - fitted.left,
                   fitted.bottom - fitted.top, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_DISPLAYCHANGE:
    case WM_SETTINGCHANGE:
    case WM_EXITSIZEMOVE: {
      const auto result = DefWindowProc(hwnd, message, wparam, lparam);
      if (message != WM_SETTINGCHANGE || wparam == SPI_SETWORKAREA)
        FitToCurrentWorkArea();
      return result;
    }
    case WM_SIZE:
      if (wparam != SIZE_MINIMIZED) ResizeChildContent();
      return 0;

    case kResizeChildContent: {
      ResizeChildContent();
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::ResizeChildContent() {
  if (!window_handle_ || !child_content_ || IsIconic(window_handle_)) return;
  if (resizing_child_) {
    // Use a posted update, rather than recursing or spinning in this callback.
    // Read the current client area when it runs: intermediate sizes can be
    // superseded during a border drag or a DPI/workarea change.
    child_resize_pending_ = true;
    return;
  }
  const RECT frame = GetClientArea();
  if (frame.right <= frame.left || frame.bottom <= frame.top) return;
  RECT child{};
  if (GetWindowRect(child_content_, &child)) {
    MapWindowPoints(nullptr, window_handle_, reinterpret_cast<POINT*>(&child), 2);
    if (EqualRect(&frame, &child)) return;
  }
  resizing_child_ = true;
  // Do not call UpdateWindow synchronously (MoveWindow(..., TRUE) does so).
  // Flutter presents the new frame itself; copied old pixels must not cover
  // the newly exposed area while the render surface is changing size.
  SetWindowPos(child_content_, nullptr, frame.left, frame.top,
               frame.right - frame.left, frame.bottom - frame.top,
               SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOCOPYBITS);
  resizing_child_ = false;
  if (child_resize_pending_) {
    child_resize_pending_ = false;
    PostMessage(window_handle_, kResizeChildContent, 0, 0);
  }
}

void Win32Window::FitToCurrentWorkArea() {
  if (!window_handle_ || fitting_window_ || IsIconic(window_handle_) ||
      IsZoomed(window_handle_)) return;
  RECT current{};
  if (!GetWindowRect(window_handle_, &current)) return;
  const auto fitted = FitToMonitorWorkArea(
      current, MonitorFromWindow(window_handle_, MONITOR_DEFAULTTONEAREST));
  if (EqualRect(&fitted, &current)) return;
  fitting_window_ = true;
  SetWindowPos(window_handle_, nullptr, fitted.left, fitted.top,
               fitted.right - fitted.left, fitted.bottom - fitted.top,
               SWP_NOZORDER | SWP_NOACTIVATE);
  fitting_window_ = false;
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  ResizeChildContent();

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
