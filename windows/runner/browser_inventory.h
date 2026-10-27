// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <windows.h>
#include <shobjidl.h>
#include <shellapi.h>
#include <tlhelp32.h>
#include <algorithm>
#include <cwctype>
#include <cwchar>
#include <string>
#include <vector>

namespace cie_browser {
struct Inventory {
  std::vector<std::string> installed;
  std::string default_browser;
  DWORD code = 0;
};
inline std::wstring Lower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  return value;
}
inline std::string BrowserId(std::wstring value) {
  value = Lower(value);
  if (value.find(L"msedge") != std::wstring::npos || value == L"microsoft edge") return "edge";
  if (value.find(L"chrome") != std::wstring::npos) return "chrome";
  if (value.find(L"firefox") != std::wstring::npos) return "firefox";
  return {};
}
inline std::wstring Read(HKEY root, const std::wstring& path,
                         const wchar_t* name, REGSAM view) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(root, path.c_str(), 0, KEY_QUERY_VALUE | view, &key) != ERROR_SUCCESS) return {};
  DWORD type = 0, bytes = 0;
  const auto query = RegQueryValueExW(key, name, nullptr, &type, nullptr, &bytes);
  if (query != ERROR_SUCCESS || bytes > 65536 || (type != REG_SZ && type != REG_EXPAND_SZ)) {
    RegCloseKey(key); return {};
  }
  std::wstring value(bytes / sizeof(wchar_t) + 1, L'\0');
  const auto result = RegQueryValueExW(key, name, nullptr, nullptr,
      reinterpret_cast<BYTE*>(value.data()), &bytes);
  RegCloseKey(key);
  if (result != ERROR_SUCCESS) return {};
  value.resize(std::wcslen(value.c_str()));
  if (type == REG_EXPAND_SZ) {
    const DWORD size = ExpandEnvironmentStringsW(value.c_str(), nullptr, 0);
    if (!size || size > 32768) return {};
    std::wstring expanded(size, L'\0');
    if (!ExpandEnvironmentStringsW(value.c_str(), expanded.data(), size)) return {};
    expanded.resize(size - 1); return expanded;
  }
  return value;
}
inline bool ExecutableExists(std::wstring path, bool command = false) {
  if (command) {
    int count = 0;
    auto args = CommandLineToArgvW(path.c_str(), &count);
    path = args && count > 0 ? args[0] : L"";
    if (args) LocalFree(args);
  }
  const DWORD attributes = path.empty() ? INVALID_FILE_ATTRIBUTES : GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY);
}
inline Inventory Discover() {
  Inventory result;
  const struct { const char* id; const wchar_t* executable; } browsers[] = {
      {"edge", L"msedge.exe"}, {"chrome", L"chrome.exe"}, {"firefox", L"firefox.exe"}};
  for (const auto& browser : browsers) {
    bool present = false;
    for (HKEY root : {HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE}) {
      for (REGSAM view : {KEY_WOW64_64KEY, KEY_WOW64_32KEY}) {
        present = present || ExecutableExists(Read(root,
            std::wstring(L"Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\") + browser.executable,
            nullptr, view));
        HKEY clients = nullptr;
        if (!present && RegOpenKeyExW(root, L"Software\\Clients\\StartMenuInternet", 0,
                                      KEY_ENUMERATE_SUB_KEYS | view, &clients) == ERROR_SUCCESS) {
          wchar_t name[256];
          for (DWORD i = 0; ; ++i) {
            DWORD size = 256;
            if (RegEnumKeyExW(clients, i, name, &size, nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS) break;
            if (BrowserId(name) != browser.id) continue;
            const auto path = std::wstring(L"Software\\Clients\\StartMenuInternet\\") + name + L"\\shell\\open\\command";
            if (ExecutableExists(Read(root, path, nullptr, view), true)) { present = true; break; }
          }
          RegCloseKey(clients);
        }
      }
    }
    if (present) result.installed.push_back(browser.id);
  }
  const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  IApplicationAssociationRegistration* registration = nullptr;
  if (SUCCEEDED(CoCreateInstance(CLSID_ApplicationAssociationRegistration, nullptr,
          CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&registration)))) {
    LPWSTR program = nullptr;
    if (SUCCEEDED(registration->QueryCurrentDefault(L"https", AT_URLPROTOCOL, AL_EFFECTIVE, &program)) && program)
      result.default_browser = BrowserId(program);
    CoTaskMemFree(program);
    registration->Release();
  }
  if (SUCCEEDED(initialized)) CoUninitialize();
  return result;
}
}  // namespace cie_browser
