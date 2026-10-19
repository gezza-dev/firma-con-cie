import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  static func systemLanguage() -> String {
    // Read the global OS preference, excluding this app's AppleLanguages override.
    let preferred = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
    guard let tag = preferred?.first, !tag.isEmpty else { return "en" }
    return tag.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first == "it" ? "it" : "en"
  }
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    applyLanguage(Self.systemLanguage())
  }
  func applyLanguage(_ language: String) {
    guard ["it", "en"].contains(language) else { return }
    UserDefaults.standard.set([language, language == "it" ? "en" : "it"], forKey: "AppleLanguages")
    // Leave only the application menu and its two useful actions. Keeping the
    // XIB actions preserves About and the normal application termination path.
    guard let root = NSApp.mainMenu, let applicationItem = root.items.first,
          let applicationMenu = applicationItem.submenu else { return }
    for item in root.items where item !== applicationItem { root.removeItem(item) }
    applicationItem.title = "CIE ID"
    applicationMenu.title = "CIE ID"
    for item in applicationMenu.items {
      if item.isAlternate {
        applicationMenu.removeItem(item)
      } else if item.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:)) {
        item.title = language == "it" ? "Informazioni su CIE ID" : "About CIE ID"
      } else if item.action == #selector(NSApplication.terminate(_:)) || item.action == #selector(quitCie(_:)) {
        item.title = language == "it" ? "Esci da CIE ID" : "Quit CIE ID"
        // A dedicated action avoids AppKit inserting the alternate "Quit and
        // Keep Windows" item. Termination still follows the standard NSApp path.
        item.action = #selector(quitCie(_:))
        item.target = self
      } else { applicationMenu.removeItem(item) }
    }
  }
  @objc private func quitCie(_ sender: Any?) { NSApp.terminate(sender) }
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
