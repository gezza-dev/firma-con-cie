// SPDX-License-Identifier: BSD-3-Clause
#include "Slot.h"
#include "P11Object.h"
#include <limits>
#include <set>
#include <stdexcept>
#include <iostream>
int main() {
    try {
        p11::CSlot slot("offline fixture");
        std::set<CK_OBJECT_HANDLE> handles;
        std::shared_ptr<p11::CP11Object> current;
        for (int i = 0; i < 32; ++i) {
            // Reuse the same shared_ptr variable: its address must never become
            // the object handle, or distinct objects receive the same handle.
            current = std::make_shared<p11::CP11Object>(CKO_PUBLIC_KEY, nullptr);
            auto handle = slot.GetIDFromObject(current);
            if (!handle || !handles.insert(handle).second ||
                slot.GetIDFromObject(current) != handle || slot.GetObjectFromID(handle) != current)
                throw std::runtime_error("Unstable or duplicate PKCS#11 object handle");
        }
        slot.dwP11ObjCnt = std::numeric_limits<CK_OBJECT_HANDLE>::max();
        auto afterWrap = slot.GetIDFromObject(std::make_shared<p11::CP11Object>(CKO_PUBLIC_KEY, nullptr));
        if (!afterWrap || handles.count(afterWrap)) throw std::runtime_error("Handle collision after counter wrap");
        std::cout << "PKCS#11 integer handles: stable, distinct, no pointer truncation, wrap collisions skipped\n";
        return 0;
    } catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}
