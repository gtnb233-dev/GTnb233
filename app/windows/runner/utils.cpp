#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <objbase.h>
#include <shlobj.h>
#include <stdio.h>
#include <windows.h>

#include <cstring>
#include <iostream>

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  // First, find the length of the string with a safe upper bound (CWE-126).
  // UNICODE_STRING_MAX_CHARS (32767) is the maximum length of a UNICODE_STRING.
  int input_length = static_cast<int>(wcsnlen(utf16_string, UNICODE_STRING_MAX_CHARS));
  // Now use that bounded length to determine the required buffer size.
  // When an explicit length is passed, WideCharToMultiByte does not include
  // the null terminator in its returned size.
  int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, nullptr, 0, nullptr, nullptr);
  std::string utf8_string;
  if (target_length == 0 || static_cast<size_t>(target_length) > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}

void EnsureDesktopShortcut(const std::vector<std::string>& args) {
  for (const auto& arg : args) {
    if (arg == "--no-desktop-shortcut") {
      return;
    }
  }

  wchar_t exe_path[MAX_PATH * 4]{};
  const DWORD exe_len =
      ::GetModuleFileNameW(nullptr, exe_path, MAX_PATH * 4);
  if (exe_len == 0 || exe_len >= MAX_PATH * 4) {
    return;
  }

  std::wstring exe_dir(exe_path, exe_len);
  const size_t sep = exe_dir.find_last_of(L"\\/");
  if (sep != std::wstring::npos) {
    exe_dir.resize(sep);
  } else {
    exe_dir.clear();
  }

  wchar_t desktop_dir[MAX_PATH]{};
  if (FAILED(::SHGetFolderPathW(nullptr, CSIDL_DESKTOPDIRECTORY, nullptr,
                               SHGFP_TYPE_CURRENT, desktop_dir)) ||
      desktop_dir[0] == L'\0') {
    return;
  }

  // Survey GT desktop shortcut
  std::wstring lnk_path(desktop_dir);
  if (!lnk_path.empty() && lnk_path.back() != L'\\' &&
      lnk_path.back() != L'/') {
    lnk_path.push_back(L'\\');
  }
  lnk_path += L"Survey GT.lnk";

  IShellLinkW* link = nullptr;
  HRESULT hr = ::CoCreateInstance(
      CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_IShellLinkW,
      reinterpret_cast<void**>(&link));
  if (FAILED(hr) || link == nullptr) {
    return;
  }

  IPersistFile* persist = nullptr;
  hr = link->QueryInterface(IID_IPersistFile,
                            reinterpret_cast<void**>(&persist));
  if (FAILED(hr) || persist == nullptr) {
    link->Release();
    return;
  }

  const DWORD attrs = ::GetFileAttributesW(lnk_path.c_str());
  if (attrs != INVALID_FILE_ATTRIBUTES &&
      SUCCEEDED(persist->Load(lnk_path.c_str(), STGM_READ))) {
    wchar_t cur_target[MAX_PATH * 4]{};
    wchar_t cur_icon[MAX_PATH * 4]{};
    int cur_icon_idx = -1;
    const HRESULT target_hr =
        link->GetPath(cur_target, MAX_PATH * 4, nullptr, 0);
    const HRESULT icon_hr =
        link->GetIconLocation(cur_icon, MAX_PATH * 4, &cur_icon_idx);
    if (SUCCEEDED(target_hr) && SUCCEEDED(icon_hr) &&
        ::_wcsicmp(cur_target, exe_path) == 0 &&
        ::_wcsicmp(cur_icon, exe_path) == 0 && cur_icon_idx == 0) {
      persist->Release();
      link->Release();
      return;
    }
  }

  link->SetPath(exe_path);
  if (!exe_dir.empty()) {
    link->SetWorkingDirectory(exe_dir.c_str());
  }
  link->SetDescription(
      L"\u5DE5\u7A0B\u6D4B\u91CF\u5DE5\u5177\u7BB1 (Survey GT)");
  link->SetIconLocation(exe_path, 0);
  persist->Save(lnk_path.c_str(), TRUE);

  persist->Release();
  link->Release();
}
