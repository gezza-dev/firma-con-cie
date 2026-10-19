// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include <ctime>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <string>

namespace cie {
inline std::string utcOffsetLabel(int minutes) {
    if (minutes == 0) return "UTC";
    const auto absolute = std::abs(minutes);
    std::string result = minutes < 0 ? "UTC-" : "UTC+";
    result += std::to_string(absolute / 60);
    if (absolute % 60) {
        char remainder[4];
        std::snprintf(remainder, sizeof(remainder), ":%02d", absolute % 60);
        result += remainder;
    }
    return result;
}
struct SigningTime {
    int offsetMinutes;
    std::string visible;
};
inline SigningTime localSigningTime(std::time_t instant) {
    std::tm local{};
#ifdef _WIN32
    if (localtime_s(&local, &instant) != 0) throw std::runtime_error("Local signing time unavailable");
    auto civil = local;
    const auto wallAsUtc = _mkgmtime(&civil);
#else
    if (!localtime_r(&instant, &local)) throw std::runtime_error("Local signing time unavailable");
    auto civil = local;
    const auto wallAsUtc = timegm(&civil);
#endif
    // Treat the local civil fields as UTC to measure this instant's actual
    // offset, including DST and year/day rollover. No global TZ changes.
    const int offset = static_cast<int>(std::difftime(wallAsUtc, instant) / 60);
    char date[32];
    if (!std::strftime(date, sizeof(date), "%d/%m/%Y %H:%M:%S", &local))
        throw std::runtime_error("Signing time formatting failed");
    return {offset, std::string(date) + " " + utcOffsetLabel(offset)};
}
}
