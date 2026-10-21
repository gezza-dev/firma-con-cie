#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  web_setup_ = std::make_unique<WebSetupChannel>(
      flutter_controller_->engine()->messenger(),
      flutter_controller_->view()->GetNativeWindow());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  web_setup_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Notify Flutter/plugins first (including DPI updates), then always apply
  // native fitting for geometry messages even if a plugin returns a result.
  const bool sizing_message = message == WM_SIZE || message == WM_DPICHANGED || message == WM_GETMINMAXINFO ||
                              message == WM_DISPLAYCHANGE || message == WM_SETTINGCHANGE ||
                              message == WM_EXITSIZEMOVE;
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result && !sizing_message) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  const auto result = Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  if (message == WM_EXITSIZEMOVE && flutter_controller_) {
    // Request a final frame after the native modal sizing loop has finished.
    flutter_controller_->ForceRedraw();
  }
  return result;
}
