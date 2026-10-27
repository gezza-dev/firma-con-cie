// SPDX-License-Identifier: BSD-3-Clause
#include "../browser_inventory.h"
#include <iostream>
#include <set>

int main() {
  if (cie_browser::BrowserId(L"MSEdgeHTM") != "edge" ||
      cie_browser::BrowserId(L"ChromeHTML") != "chrome" ||
      cie_browser::BrowserId(L"FirefoxURL-123") != "firefox" ||
      !cie_browser::BrowserId(L"unrelated-program").empty() ||
      cie_browser::ExecutableExists(L"")) return 1;
  // Read-only discovery against this machine. No browser is started and no
  // registry, profile, certificate store or smart card is modified.
  const auto inventory = cie_browser::Discover();
  const std::set<std::string> allowed = {"edge", "chrome", "firefox"};
  std::set<std::string> unique;
  for (const auto& id : inventory.installed) {
    if (!allowed.count(id) || !unique.insert(id).second) return 2;
  }
  if (!inventory.default_browser.empty() &&
      !allowed.count(inventory.default_browser)) return 3;
  if (inventory.code != ERROR_SUCCESS) return 4;
  std::cout << "Read-only inventory passed; installed=" << unique.size()
            << "; default=" << inventory.default_browser << "\n";
  return 0;
}
