// SPDX-License-Identifier: BSD-3-Clause
import Foundation

// Configuration presence alone does not reflect the user's PlugInKit election.
// Observation never changes elections. Activation is an explicit host action;
// it never registers bundles, changes other IDs, or authenticates a card.
enum WebComponentActivation {
  static let classID = "it.giancarloezza.CIEID.FlutterPrototype.WebToken"
  static let activationArguments = ["-e", "use", "-i", classID, "-p", "com.apple.ctk-tokens"]

  static func activate(bundled: Bool, command: ([String]) -> String? = run) -> Bool {
    guard bundled else { return false }
    return command(activationArguments) != nil
  }

  static func state(bundled: Bool, driverPresent: Bool, election: String?) -> String {
    guard bundled else { return "missing" }
    guard let election = election else { return "unknown" }
    let matches = election.split(separator: "\n").compactMap { line -> Character? in
      let text = line.trimmingCharacters(in: .whitespaces)
      for marker in ["+", "-", "!", "=", "?", ""] {
        guard marker.isEmpty || text.hasPrefix(marker) else { continue }
        let record = String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        if record.hasPrefix(classID + "(") { return marker.first ?? " " }
      }
      return nil
    }
    guard matches.count == 1, let marker = matches.first else { return "unavailable" }
    if marker == "-" { return "disabled" }
    if marker == "?" { return "unknown" }
    if marker == "!" || marker == "=" { return "unavailable" }
    return driverPresent ? "enabled" : "unavailable"
  }

  static func election() -> String? {
    return run(["-m", "-i", classID, "-p", "com.apple.ctk-tokens"])
  }

  private static func run(_ arguments: [String]) -> String? {
    let process = Process(), output = Pipe(), done = DispatchSemaphore(value: 0)
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.terminationHandler = { _ in done.signal() }
    do { try process.run() } catch { return nil }
    guard done.wait(timeout: .now() + 2) == .success else {
      process.terminate()
      return nil
    }
    guard process.terminationStatus == 0 else { return nil }
    return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
  }
}
