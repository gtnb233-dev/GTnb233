#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  EnsureDesktopShortcut(command_line_arguments);

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);

  // 根据光标所在显示器的可用工作区居中窗口，并按该显示器 DPI 计算逻辑尺寸。
  POINT cursor_pt{0, 0};
  ::GetCursorPos(&cursor_pt);
  HMONITOR monitor = ::MonitorFromPoint(cursor_pt, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO mi{};
  mi.cbSize = sizeof(mi);
  double scale = 1.0;
  RECT work{0, 0, 1920, 1080};
  if (::GetMonitorInfo(monitor, &mi)) {
    work = mi.rcWork;
  }
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  if (dpi > 0) {
    scale = dpi / 96.0;
  }
  const int work_w_log = static_cast<int>((work.right - work.left) / scale);
  const int work_h_log = static_cast<int>((work.bottom - work.top) / scale);
  const unsigned int target_w =
      static_cast<unsigned int>(std::max(480, std::min(1180, work_w_log - 40)));
  const unsigned int target_h =
      static_cast<unsigned int>(std::max(600, std::min(780, work_h_log - 40)));
  const unsigned int origin_x = static_cast<unsigned int>(
      std::max(0, static_cast<int>(work.left / scale) +
                      (work_w_log - static_cast<int>(target_w)) / 2));
  const unsigned int origin_y = static_cast<unsigned int>(
      std::max(0, static_cast<int>(work.top / scale) +
                      (work_h_log - static_cast<int>(target_h)) / 2));

  Win32Window::Point origin(origin_x, origin_y);
  Win32Window::Size size(target_w, target_h);
  if (!window.Create(L"Survey GT", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
