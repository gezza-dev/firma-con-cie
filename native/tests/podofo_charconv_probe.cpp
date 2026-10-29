// SPDX-License-Identifier: BSD-3-Clause
// Compiled against the actual extracted PoDoFo header and pinned LLVM libc++.
// No PDF, card, certificate or user state is accessed.
#include "charconv_compat.h"
#include <cmath>
#include <string_view>

template<class T>
bool check(T value, int precision, std::string_view expected) {
  char buffer[128];
  auto text = std::to_chars(buffer, buffer + sizeof(buffer), value,
                            std::chars_format::fixed, precision);
  if (text.ec != std::errc{} || std::string_view(buffer, text.ptr - buffer) != expected)
    return false;
  double parsed = 0;
  auto result = std::from_chars(buffer, text.ptr, parsed, std::chars_format::fixed);
  return result.ec == std::errc{} && result.ptr == text.ptr &&
         parsed == static_cast<double>(value) && std::signbit(parsed) == std::signbit(value);
}

int main() {
  if (!check(1.25f, 4, "1.2500") || !check(-2.5, 6, "-2.500000") ||
      !check(-0.0, 2, "-0.00")) return 1;
  char short_buffer[1];
  auto small = std::to_chars(short_buffer, short_buffer + 1, 123.45,
                             std::chars_format::fixed, 2);
  if (small.ec != std::errc::value_too_large) return 2;
  double parsed = 0;
  const char invalid[] = "invalid";
  auto bad = std::from_chars(invalid, invalid + 7, parsed, std::chars_format::fixed);
  return bad.ec == std::errc::invalid_argument && bad.ptr == invalid ? 0 : 3;
}
