#include "flutter_window.h"

#include <commdlg.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cstdint>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return {};
  }
  const int needed = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  if (needed <= 0) {
    return {};
  }
  std::wstring wide(static_cast<size_t>(needed), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        wide.data(), needed);
  return wide;
}

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

std::wstring BuildWin32FileFilter(const std::string& filter_label,
                                  const std::vector<std::string>& extensions,
                                  std::wstring* default_ext) {
  std::wstring filter;
  if (!extensions.empty()) {
    std::wstring patterns;
    for (size_t i = 0; i < extensions.size(); ++i) {
      std::string ext = extensions[i];
      if (!ext.empty() && ext[0] == '.') {
        ext.erase(0, 1);
      }
      if (ext.empty()) {
        continue;
      }
      std::wstring wext = Utf16FromUtf8(ext);
      if (default_ext && default_ext->empty()) {
        *default_ext = wext;
      }
      if (!patterns.empty()) {
        patterns += L";";
      }
      patterns += L"*." + wext;
    }
    if (!patterns.empty()) {
      std::wstring label = filter_label.empty()
                               ? L"Supported Files"
                               : Utf16FromUtf8(filter_label);
      filter += label + L" (" + patterns + L")";
      filter.push_back(L'\0');
      filter += patterns;
      filter.push_back(L'\0');
    }
  }
  filter += L"All Files (*.*)";
  filter.push_back(L'\0');
  filter += L"*.*";
  filter.push_back(L'\0');
  filter.push_back(L'\0');
  return filter;
}

std::optional<std::string> ShowNativeFileDialog(
    HWND owner, bool save, const flutter::EncodableMap* args) {
  std::string suggested_name;
  std::string filter_label;
  std::vector<std::string> extensions;

  if (args) {
    if (auto it = args->find(flutter::EncodableValue("suggestedName"));
        it != args->end()) {
      if (const auto* s = std::get_if<std::string>(&it->second)) {
        suggested_name = *s;
      }
    }
    if (auto it = args->find(flutter::EncodableValue("filterLabel"));
        it != args->end()) {
      if (const auto* s = std::get_if<std::string>(&it->second)) {
        filter_label = *s;
      }
    }
    if (auto it = args->find(flutter::EncodableValue("extensions"));
        it != args->end()) {
      if (const auto* list = std::get_if<flutter::EncodableList>(&it->second)) {
        for (const auto& item : *list) {
          if (const auto* s = std::get_if<std::string>(&item)) {
            extensions.push_back(*s);
          }
        }
      }
    }
  }

  std::wstring default_ext;
  std::wstring filter =
      BuildWin32FileFilter(filter_label, extensions, &default_ext);

  std::vector<wchar_t> file_buf(4096, L'\0');
  if (save && !suggested_name.empty()) {
    std::wstring wname = Utf16FromUtf8(suggested_name);
    const size_t copy_len =
        (std::min)(wname.size(), file_buf.size() - 1);
    std::copy_n(wname.data(), copy_len, file_buf.data());
  }

  OPENFILENAMEW ofn{};
  ofn.lStructSize = sizeof(ofn);
  ofn.hwndOwner = owner;
  ofn.lpstrFilter = filter.c_str();
  ofn.nFilterIndex = 1;
  ofn.lpstrFile = file_buf.data();
  ofn.nMaxFile = static_cast<DWORD>(file_buf.size());
  ofn.lpstrDefExt =
      (save && !default_ext.empty()) ? default_ext.c_str() : nullptr;
  ofn.Flags = OFN_EXPLORER | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR |
              (save ? OFN_OVERWRITEPROMPT : OFN_FILEMUSTEXIST);

  const BOOL ok = save ? ::GetSaveFileNameW(&ofn) : ::GetOpenFileNameW(&ofn);
  if (!ok) {
    return std::nullopt;
  }
  return Utf8FromUtf16(file_buf.data());
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
        const auto& method = call.method_name();
        if (method == "accentColor") {
          auto accent = ReadWindowsAccentColor();
          if (accent.has_value()) {
            result->Success(flutter::EncodableValue(*accent));
          } else {
            result->Success();
          }
          return;
        }
        if (method == "setWindowBrightness") {
          if (const auto* is_dark = std::get_if<bool>(call.arguments())) {
            SetDarkMode(*is_dark);
          }
          result->Success();
          return;
        }
        if (method == "setWindowTitle") {
          if (const auto* title = std::get_if<std::string>(call.arguments())) {
            if (HWND hwnd = GetHandle()) {
              ::SetWindowTextW(hwnd, Utf16FromUtf8(*title).c_str());
            }
          }
          result->Success();
          return;
        }
        if (method == "windowMinimize") {
          if (HWND hwnd = GetHandle()) {
            ::ShowWindow(hwnd, SW_MINIMIZE);
          }
          result->Success();
          return;
        }
        if (method == "windowMaximizeToggle") {
          bool maximized = false;
          if (HWND hwnd = GetHandle()) {
            if (::IsZoomed(hwnd)) {
              ::ShowWindow(hwnd, SW_RESTORE);
              maximized = false;
            } else {
              ::ShowWindow(hwnd, SW_MAXIMIZE);
              maximized = true;
            }
          }
          result->Success(flutter::EncodableValue(maximized));
          return;
        }
        if (method == "windowIsMaximized") {
          HWND hwnd = GetHandle();
          const bool maximized = hwnd != nullptr && ::IsZoomed(hwnd) != FALSE;
          result->Success(flutter::EncodableValue(maximized));
          return;
        }
        if (method == "windowClose") {
          if (HWND hwnd = GetHandle()) {
            ::PostMessage(hwnd, WM_CLOSE, 0, 0);
          }
          result->Success();
          return;
        }
        if (method == "windowStartDrag") {
          if (HWND hwnd = GetHandle()) {
            ::ReleaseCapture();
            ::SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
          }
          result->Success();
          return;
        }
        if (method == "setKeepScreenOn") {
          if (const auto* enabled = std::get_if<bool>(call.arguments())) {
            const auto state = *enabled ? ES_CONTINUOUS | ES_DISPLAY_REQUIRED
                                        : ES_CONTINUOUS;
            ::SetThreadExecutionState(state);
          }
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  files_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "survey/files",
          &flutter::StandardMethodCodec::GetInstance());
  files_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto& method = call.method_name();
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (method == "pickSaveFile") {
          auto path = ShowNativeFileDialog(GetHandle(), true, args);
          if (path.has_value()) {
            result->Success(flutter::EncodableValue(*path));
          } else {
            result->Success();
          }
          return;
        }
        if (method == "pickOpenFile") {
          auto path = ShowNativeFileDialog(GetHandle(), false, args);
          if (path.has_value()) {
            result->Success(flutter::EncodableValue(*path));
          } else {
            result->Success();
          }
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
  files_channel_.reset();
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
