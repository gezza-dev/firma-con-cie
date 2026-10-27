// SPDX-License-Identifier: BSD-3-Clause
import AppKit

enum MacBrowserInventory {
  private static let browsers = [
    ("safari", "com.apple.Safari"), ("chrome", "com.google.Chrome"),
    ("firefox", "org.mozilla.firefox"), ("edge", "com.microsoft.edgemac")
  ]

  static func firefoxState(version: String?) -> String {
    guard let version = version,
          let majorText = version.split(separator: ".", omittingEmptySubsequences: false).first,
          !majorText.isEmpty,
          majorText.allSatisfy({ $0.isASCII && $0.isNumber }),
          let major = Int(majorText) else { return "browser_version_unavailable" }
    // Firefox 90+ integrates macOS client certificates by default. This checks
    // local prerequisites, not private preferences, enterprise policy or a login.
    return major >= 90 ? "configured" : "browser_version_unsupported"
  }

  static func report(installed: [String], defaultBrowser: String,
                     firefoxVersion: String?) -> [String: Any] {
    let known = Set(browsers.map { $0.0 })
    let installed = installed.filter { known.contains($0) }
    var states = [String: String]()
    if installed.contains("firefox") {
      states["firefox"] = firefoxState(version: firefoxVersion)
    }
    return ["ok": true, "installed": installed,
            "default": known.contains(defaultBrowser) ? defaultBrowser : "",
            "nativeStates": states]
  }

  static func read() -> [String: Any] {
    let workspace = NSWorkspace.shared
    let applications = browsers.compactMap { browser -> (String, URL)? in
      guard let url = workspace.urlForApplication(withBundleIdentifier: browser.1) else { return nil }
      return (browser.0, url)
    }
    let selected = workspace.urlForApplication(
      toOpen: URL(string: "https://www.cartaidentita.interno.gov.it/")!)
      .flatMap { Bundle(url: $0)?.bundleIdentifier }
    let defaultBrowser = browsers.first { $0.1 == selected }?.0 ?? ""
    let firefoxVersion = applications.first { $0.0 == "firefox" }
      .flatMap { Bundle(url: $0.1)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
    // Launch Services and installed-app metadata only: no profile, NSS/key
    // database, browser process, permission prompt or preference is touched.
    return report(installed: applications.map { $0.0 },
                  defaultBrowser: defaultBrowser, firefoxVersion: firefoxVersion)
  }
}
