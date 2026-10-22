#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>
#include <uxtheme.h>
#include <windowsx.h>

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

RECT FitToMonitorWorkArea(const RECT& proposed, HMONITOR monitor,
                          bool center = false) {
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfo(monitor, &info)) return proposed;
  const auto fit = center ? cie_window_center_rect : cie_window_fit_rect;
  const auto fitted = fit(
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
  buffered_paint_initialized_ = SUCCEEDED(BufferedPaintInit());
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
  if (buffered_paint_initialized_) BufferedPaintUnInit();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size,
                         bool center_in_work_area) {
  Destroy();
  custom_caption_ = false;
  caption_frame_height_ = -1;
  caption_background_ = DWMWA_COLOR_DEFAULT;

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
  const RECT fitted = FitToMonitorWorkArea(requested, monitor, center_in_work_area);
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
  UpdateCaptionFrame();

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
  if (custom_caption_) {
    if (message == WM_NCHITTEST) {
      // After maximization DWM can report the extended caption as client/drag
      // area even over its visible buttons. Use the OS button rectangles (the
      // same ones exposed to accessibility), before either drag fallback.
      TITLEBARINFOEX title{};
      title.cbSize = sizeof(title);
      SendMessage(hwnd, WM_GETTITLEBARINFOEX, 0, reinterpret_cast<LPARAM>(&title));
      const POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      const struct { int index; LRESULT hit; } buttons[] = {
          {2, HTMINBUTTON}, {3, HTMAXBUTTON}, {5, HTCLOSE}};
      for (const auto& button : buttons) {
        if (!(title.rgstate[button.index] & (STATE_SYSTEM_UNAVAILABLE |
              STATE_SYSTEM_INVISIBLE | STATE_SYSTEM_OFFSCREEN)) &&
            PtInRect(&title.rgrect[button.index], point))
          return button.hit;
      }
    }
    LRESULT dwm_result = 0;
    if (DwmDefWindowProc(hwnd, message, wparam, lparam, &dwm_result))
      return dwm_result;
    if (message == WM_NCCALCSIZE && wparam) {
      auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
      const LONG top = params->rgrc[0].top;
      DefWindowProc(hwnd, message, wparam, lparam);
      // Preserve OS side/bottom borders. Only the caption becomes client area.
      // Maximized windows retain the invisible frame inset above the workarea.
      params->rgrc[0].top = top + (IsZoomed(hwnd)
          ? GetSystemMetricsForDpi(SM_CYFRAME, current_dpi_) +
            GetSystemMetricsForDpi(SM_CXPADDEDBORDER, current_dpi_) : 0);
      return 0;
    }
    if (message == WM_NCHITTEST) {
      const auto native_hit = DefWindowProc(hwnd, message, wparam, lparam);
      if (native_hit != HTCLIENT) return native_hit;
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(hwnd, &point);
      const int border = GetSystemMetricsForDpi(SM_CYFRAME, current_dpi_) +
                         GetSystemMetricsForDpi(SM_CXPADDEDBORDER, current_dpi_);
      RECT client{};
      GetClientRect(hwnd, &client);
      if (!IsZoomed(hwnd) && point.y >= 0 && point.y < border) {
        if (point.x < border) return HTTOPLEFT;
        if (point.x >= client.right - border) return HTTOPRIGHT;
        return HTTOP;
      }
      if (point.y >= 0 && point.y < CaptionHeight()) {
        if (point.x < Scale(32, current_dpi_)) return HTSYSMENU;
        return HTCAPTION;
      }
      return HTCLIENT;
    }
    if (message == WM_PAINT) {
      PAINTSTRUCT paint{};
      HDC dc = BeginPaint(hwnd, &paint);
      PaintCaption(dc);
      EndPaint(hwnd, &paint);
      return 0;
    }
  }
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
      UpdateCaptionFrame();
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
      if (message == WM_SETTINGCHANGE) {
        UpdateTheme(hwnd);
        UpdateCaptionFrame();
        ResizeChildContent();
      }
      return result;
    }
    case WM_SIZE:
      UpdateCaptionFrame();
      InvalidateCaption();
      if (wparam != SIZE_MINIMIZED) ResizeChildContent();
      return 0;

    case kResizeChildContent: {
      ResizeChildContent();
      return 0;
    }

    case WM_ACTIVATE:
      active_caption_ = LOWORD(wparam) != WA_INACTIVE;
      UpdateCaptionFrame();
      InvalidateCaption();
      if (active_caption_ && child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return DefWindowProc(hwnd, message, wparam, lparam);

    case WM_SETTEXT: {
      const auto result = DefWindowProc(hwnd, message, wparam, lparam);
      InvalidateCaption();
      return result;
    }

    case WM_THEMECHANGED:
    case WM_DWMCOMPOSITIONCHANGED:
    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      UpdateCaptionFrame();
      ResizeChildContent();
      InvalidateCaption();
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

int Win32Window::CaptionHeight() const {
  if (!custom_caption_) return 0;
  return GetSystemMetricsForDpi(SM_CYCAPTION, current_dpi_) +
      (IsZoomed(window_handle_) ? 0 :
       GetSystemMetricsForDpi(SM_CYFRAME, current_dpi_) +
       GetSystemMetricsForDpi(SM_CXPADDEDBORDER, current_dpi_));
}

void Win32Window::UpdateCaptionFrame() {
  if (!window_handle_) return;
  HIGHCONTRAST contrast{};
  contrast.cbSize = sizeof(contrast);
  SystemParametersInfo(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast, 0);
  BOOL composition = FALSE;
  DwmIsCompositionEnabled(&composition);
  const bool enabled = composition && !(contrast.dwFlags & HCF_HIGHCONTRASTON);
  if (enabled != custom_caption_) {
    custom_caption_ = enabled;
    SetWindowPos(window_handle_, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                 SWP_FRAMECHANGED);
  }
  const MARGINS margins{0, 0, CaptionHeight(), 0};
  if (margins.cyTopHeight != caption_frame_height_) {
    caption_frame_height_ = margins.cyTopHeight;
    DwmExtendFrameIntoClientArea(window_handle_, &margins);
  }
  BOOL dark = FALSE;
  DwmGetWindowAttribute(window_handle_, DWMWA_USE_IMMERSIVE_DARK_MODE,
                       &dark, sizeof(dark));
  const COLORREF background = custom_caption_
      ? (dark ? RGB(32, 32, 32) : RGB(243, 243, 243)) : DWMWA_COLOR_DEFAULT;
  // Available on Windows 11; older Windows keeps its native caption color.
  if (background != caption_background_) {
    caption_background_ = background;
    DwmSetWindowAttribute(window_handle_, DWMWA_CAPTION_COLOR,
                         &background, sizeof(background));
  }
  InvalidateCaption();
}

void Win32Window::InvalidateCaption() {
  if (!window_handle_ || !custom_caption_) return;
  RECT caption{};
  GetClientRect(window_handle_, &caption);
  caption.bottom = std::min(caption.bottom, LONG(CaptionHeight()));
  InvalidateRect(window_handle_, &caption, FALSE);
}

void Win32Window::PaintCaption(HDC dc) {
  RECT caption{};
  GetClientRect(window_handle_, &caption);
  caption.bottom = std::min(caption.bottom, LONG(CaptionHeight()));
  if (caption.right <= 0 || caption.bottom <= 0) return;
  BOOL dark = FALSE;
  DwmGetWindowAttribute(window_handle_, DWMWA_USE_IMMERSIVE_DARK_MODE,
                       &dark, sizeof(dark));
  const COLORREF background = dark ? RGB(32, 32, 32) : RGB(243, 243, 243);
  const COLORREF foreground = dark
      ? (active_caption_ ? RGB(255, 255, 255) : RGB(170, 170, 170))
      : (active_caption_ ? RGB(0, 0, 0) : RGB(100, 100, 100));
  HDC buffer = nullptr;
  BP_PAINTPARAMS parameters{};
  parameters.cbSize = sizeof(parameters);
  parameters.dwFlags = BPPF_ERASE;
  HPAINTBUFFER paint = BeginBufferedPaint(dc, &caption, BPBF_TOPDOWNDIB,
                                         &parameters, &buffer);
  if (!paint) buffer = dc;
  HBRUSH brush = CreateSolidBrush(background);
  FillRect(buffer, &caption, brush);
  DeleteObject(brush);
  NONCLIENTMETRICS metrics{};
  metrics.cbSize = sizeof(metrics);
  HFONT font = nullptr;
  if (SystemParametersInfoForDpi(SPI_GETNONCLIENTMETRICS, sizeof(metrics),
                                  &metrics, 0, current_dpi_))
    font = CreateFontIndirect(&metrics.lfCaptionFont);
  HGDIOBJ old_font = SelectObject(buffer, font ? font : GetStockObject(DEFAULT_GUI_FONT));
  SetBkMode(buffer, TRANSPARENT);
  SetTextColor(buffer, foreground);
  const int icon_size = GetSystemMetricsForDpi(SM_CXSMICON, current_dpi_);
  HICON icon = reinterpret_cast<HICON>(GetClassLongPtr(window_handle_, GCLP_HICON));
  if (icon) DrawIconEx(buffer, Scale(8, current_dpi_),
      caption.top + (caption.bottom - caption.top - icon_size) / 2, icon,
      icon_size, icon_size, 0, nullptr, DI_NORMAL);
  // Symmetric space keeps the text centered on the entire window, rather
  // than the asymmetric gap between the left icon and the native buttons.
  int reserve = Scale(150, current_dpi_);
  RECT buttons{};
  if (SUCCEEDED(DwmGetWindowAttribute(window_handle_, DWMWA_CAPTION_BUTTON_BOUNDS,
                                      &buttons, sizeof(buttons))) && buttons.left > 0) {
    RECT outer{};
    GetWindowRect(window_handle_, &outer);
    reserve = std::max(reserve, int(outer.right - outer.left - buttons.left));
  }
  // The top resize strip is part of the visible caption. Excluding it would
  // push the text down in normal windows, but not in maximized windows.
  RECT text{reserve, caption.top, std::max(LONG(reserve), caption.right - reserve), caption.bottom};
  wchar_t title[256]{};
  GetWindowText(window_handle_, title, 256);
  DrawText(buffer, title, -1, &text, DT_CENTER | DT_VCENTER | DT_SINGLELINE |
                                    DT_END_ELLIPSIS | DT_NOPREFIX);
  SelectObject(buffer, old_font);
  if (font) DeleteObject(font);
  if (paint) {
    BufferedPaintSetAlpha(paint, nullptr, 255);
    // Leave native caption buttons transparent to DWM. An opaque client
    // buffer here would cover their glyphs even though hit testing still works.
    RECT native_buttons{std::max(0L, caption.right - Scale(138, current_dpi_)),
                        0, caption.right, caption.bottom};
    if (buttons.left > 0) {
      RECT outer{};
      GetWindowRect(window_handle_, &outer);
      POINT origin{};
      ClientToScreen(window_handle_, &origin);
      native_buttons.left = std::max(0L, buttons.left - (origin.x - outer.left));
    }
    BufferedPaintClear(paint, &native_buttons);
    EndBufferedPaint(paint, TRUE);
  }
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
  RECT frame{};
  GetClientRect(window_handle_, &frame);
  frame.top = std::min(frame.bottom, LONG(CaptionHeight()));
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
