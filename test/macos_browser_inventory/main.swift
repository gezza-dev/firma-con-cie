// SPDX-License-Identifier: BSD-3-Clause
import Foundation

var checks = 0
func verify(_ condition: @autoclosure () -> Bool) {
  precondition(condition())
  checks += 1
}

for version in ["90.0", "128.12.0esr", "145.0.2", "150.0a1"] {
  verify(MacBrowserInventory.firefoxState(version: version) == "configured")
}
for version in ["89.0.2", "78.15.0esr"] {
  verify(MacBrowserInventory.firefoxState(version: version) == "browser_version_unsupported")
}
let invalidVersions: [String?] = [nil, "", ".90", "unknown", "-90.0", "９０.0"]
for version in invalidVersions {
  verify(MacBrowserInventory.firefoxState(version: version) == "browser_version_unavailable")
}
let supported = MacBrowserInventory.report(installed: ["safari", "firefox"],
                                          defaultBrowser: "firefox", firefoxVersion: "145.0.2")
verify((supported["nativeStates"] as? [String: String])?["firefox"] == "configured")
verify(supported["default"] as? String == "firefox")
let old = MacBrowserInventory.report(installed: ["safari", "firefox"],
                                    defaultBrowser: "safari", firefoxVersion: "89.0")
verify((old["nativeStates"] as? [String: String])?["firefox"] == "browser_version_unsupported")
let missing = MacBrowserInventory.report(installed: ["firefox"],
                                        defaultBrowser: "unknown", firefoxVersion: nil)
verify((missing["nativeStates"] as? [String: String])?["firefox"] == "browser_version_unavailable")
verify(missing["default"] as? String == "")
let absent = MacBrowserInventory.report(installed: ["safari", "untrusted"],
                                       defaultBrowser: "safari", firefoxVersion: "145.0")
verify((absent["nativeStates"] as? [String: String])?.isEmpty == true)
verify(absent["installed"] as? [String] == ["safari"])
print("\(checks) macOS browser capability checks passed without accessing profiles.")

if CommandLine.arguments.contains("--inspect-installed") {
  let actual = MacBrowserInventory.read()
  let data = try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys])
  print(String(decoding: data, as: UTF8.self))
}
