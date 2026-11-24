#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <optional>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::optional<int64_t> ReadWindowsAccentColor() {
  DWORD abgr = 0;
  DWORD size = sizeof(abgr);
  LSTATUS status = ::RegGetValueW(
      HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\DWM",
      L"AccentColor", RRF_RT_REG_DWORD, nullptr, &abgr, &size);
  if (status != ERROR_SUCCESS) {
    return std::nullopt;
  }
  const uint32_t r = abgr & 0xFF;
  const uint32_t g = (abgr >> 8) & 0xFF;
  const uint32_t b = (abgr >> 16) & 0xFF;
  const int64_t argb =
      static_cast<int64_t>(0xFF000000u | (r << 16) | (g << 8) | b);
  return argb;
}

}  // namespace

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

  theme_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "survey/theme",
          &flutter::StandardMethodCodec::GetInstance());
  theme_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "accentColor") {
          auto accent = ReadWindowsAccentColor();
          if (accent.has_value()) {
            result->Success(flutter::EncodableValue(*accent));
          } else {
            result->Success();
          }
          return;
        }
        if (call.method_name() == "setWindowBrightness") {
          if (const auto* is_dark = std::get_if<bool>(call.arguments())) {
            SetDarkMode(*is_dark);
          }
          result->Success();
          return;
        }
        result->NotImplemented();
      });

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
  theme_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
