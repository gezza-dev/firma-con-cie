// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <cstdio>
#include <filesystem>
#include <string>
#include <cerrno>
#include <algorithm>
#include <cctype>
inline bool cieContainsInsensitive(const char* value, const char* part) {
    std::string text(value), needle(part);
    auto lower = [](unsigned char c) { return static_cast<char>(std::tolower(c)); };
    std::transform(text.begin(), text.end(), text.begin(), lower);
    std::transform(needle.begin(), needle.end(), needle.begin(), lower);
    return text.find(needle) != std::string::npos;
}
#ifdef _WIN32
#include <windows.h>
// The public C API and Dart both use UTF-8, independent of the process locale.
inline FILE* cieFopen(const char* name, const char* mode) {
    if (!name || !mode) { errno = EINVAL; return nullptr; }
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name, -1, nullptr, 0);
    if (!count) { errno = EINVAL; return nullptr; }
    std::wstring path(count, L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name, -1, path.data(), count);
    std::wstring wideMode;
    for (auto p = mode; *p; ++p) wideMode.push_back(static_cast<unsigned char>(*p));
    return _wfopen(path.c_str(), wideMode.c_str());
}
#else
inline FILE* cieFopen(const char* name, const char* mode) { return std::fopen(name, mode); }
#endif

#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
inline FILE* cieOpenRegularNoFollow(const char* name) {
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name, -1, nullptr, 0);
    if (!count) return nullptr;
    std::wstring path(count, L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name, -1, path.data(), count);
    HANDLE handle = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
        OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (handle == INVALID_HANDLE_VALUE) return nullptr;
    BY_HANDLE_FILE_INFORMATION info{};
    if (!GetFileInformationByHandle(handle, &info) ||
        (info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY))) {
        CloseHandle(handle); return nullptr;
    }
    int descriptor = _open_osfhandle(reinterpret_cast<intptr_t>(handle), _O_RDONLY | _O_TEXT);
    if (descriptor == -1) { CloseHandle(handle); return nullptr; }
    FILE* file = _fdopen(descriptor, "rt");
    if (!file) _close(descriptor);
    return file;
}
#else
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
inline FILE* cieOpenRegularNoFollow(const char* name) {
    int descriptor = open(name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (descriptor < 0) return nullptr;
    struct stat info{};
    if (fstat(descriptor, &info) || !S_ISREG(info.st_mode)) { close(descriptor); return nullptr; }
    FILE* file = fdopen(descriptor, "r");
    if (!file) close(descriptor);
    return file;
}
#endif
