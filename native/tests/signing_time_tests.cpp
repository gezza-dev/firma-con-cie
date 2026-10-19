// SPDX-License-Identifier: BSD-3-Clause
#include "Native/SigningTime.h"
#include <iostream>
#include <utility>

static void check(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }
#ifndef _WIN32
static std::time_t instant(int year, int month, int day, int hour, int minute) {
    std::tm utc{}; utc.tm_year=year-1900; utc.tm_mon=month-1; utc.tm_mday=day;
    utc.tm_hour=hour; utc.tm_min=minute; return timegm(&utc);
}
static void zone(const char* name, std::time_t time, int offset, const char* label) {
    setenv("TZ",name,1); tzset(); // Only this test process; never OS settings.
    const auto result=cie::localSigningTime(time);
    check(result.offsetMinutes==offset,"Wrong timezone/DST offset");
    check(result.visible==label,"Wrong local signing label");
}
#endif
int main() {
    try {
        for (const auto& c : {std::pair<int,const char*>{0,"UTC"}, {60,"UTC+1"}, {120,"UTC+2"},
             {-60,"UTC-1"}, {-120,"UTC-2"}, {330,"UTC+5:30"}, {345,"UTC+5:45"},
             {-210,"UTC-3:30"}, {765,"UTC+12:45"}})
            check(cie::utcOffsetLabel(c.first)==c.second,"Wrong offset formatting");
#ifndef _WIN32
        zone("Europe/Rome",instant(2026,1,15,12,0),60,"15/01/2026 13:00:00 UTC+1");
        zone("Europe/Rome",instant(2026,7,15,12,0),120,"15/07/2026 14:00:00 UTC+2");
        zone("Europe/Rome",instant(2026,3,29,0,30),60,"29/03/2026 01:30:00 UTC+1");
        zone("Europe/Rome",instant(2026,3,29,1,30),120,"29/03/2026 03:30:00 UTC+2");
        zone("Europe/Rome",instant(2026,10,25,0,30),120,"25/10/2026 02:30:00 UTC+2");
        zone("Europe/Rome",instant(2026,10,25,1,30),60,"25/10/2026 02:30:00 UTC+1");
        zone("America/New_York",instant(2026,1,15,12,0),-300,"15/01/2026 07:00:00 UTC-5");
        zone("America/New_York",instant(2026,7,15,12,0),-240,"15/07/2026 08:00:00 UTC-4");
        zone("Asia/Kolkata",instant(2026,1,15,12,0),330,"15/01/2026 17:30:00 UTC+5:30");
        zone("Asia/Kathmandu",instant(2026,12,31,23,30),345,"01/01/2027 05:15:00 UTC+5:45");
        zone("UTC",instant(2026,1,15,12,0),0,"15/01/2026 12:00:00 UTC");
#else
        check(!cie::localSigningTime(std::time(nullptr)).visible.empty(),"Windows local time unavailable");
#endif
        std::cout<<"PASS local signing time, DST transitions, negative and fractional UTC offsets\n";
        return 0;
    } catch (const std::exception& e) { std::cerr<<e.what()<<'\n'; return 1; }
}
