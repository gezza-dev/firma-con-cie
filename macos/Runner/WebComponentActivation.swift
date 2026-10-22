// SPDX-License-Identifier: BSD-3-Clause
import Foundation

// Observe the selected registry record, not merely the existence of a driver.
// Repair is explicit and only registers this host's embedded extension. It never
// unregisters other bundles, changes card data, or authenticates a card.
enum WebComponentActivation {
  static let classID = "it.giancarloezza.CIEID.FlutterPrototype.WebToken"
  static let activationArguments = ["-e", "use", "-i", classID, "-p", "com.apple.ctk-tokens"]
  static let queryArguments = ["-m", "-v", "-i", classID, "-p", "com.apple.ctk-tokens"]
  static var embeddedURL: URL? {
    Bundle.main.builtInPlugInsURL?.appendingPathComponent("CIEPrototypeToken.appex")
  }

  struct Identity {
    let url: URL
    let version: String
    let build: String
    init?(_ url: URL) {
      let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
      guard canonical.pathExtension == "appex",
            let data = try? Data(contentsOf: canonical.appendingPathComponent("Contents/Info.plist")),
            let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
            info["CFBundleIdentifier"] as? String == classID,
            let ext = info["NSExtension"] as? [String: Any],
            ext["NSExtensionPointIdentifier"] as? String == "com.apple.ctk-tokens",
            let version = info["CFBundleShortVersionString"] as? String, !version.isEmpty,
            let build = info["CFBundleVersion"] as? String, !build.isEmpty,
            let name = info["CFBundleExecutable"] as? String, !name.isEmpty,
            !name.contains("/"), name != ".", name != "..",
            FileManager.default.isExecutableFile(atPath: canonical.appendingPathComponent("Contents/MacOS/" + name).path) else { return nil }
      self.url = canonical; self.version = version; self.build = build
    }
  }

  struct Registration {
    let marker: Character
    let version: String
    let url: URL
  }

  struct Assessment {
    let state: String
    let expected: Identity?
    let selected: Identity?
    let pathMatches: Bool
    let versionMatches: Bool
    var needsUpdate: Bool { state == "path_mismatch" || state == "version_mismatch" }
    var diagnostics: [String: Any] {
      ["activationState": state, "componentPathMatches": pathMatches,
       "componentVersionMatches": versionMatches, "componentNeedsUpdate": needsUpdate,
       "componentHostOutdated": state == "host_outdated",
       "componentExpectedVersion": expected?.version ?? "", "componentExpectedBuild": expected?.build ?? "",
       "componentSelectedVersion": selected?.version ?? "", "componentSelectedBuild": selected?.build ?? ""]
    }
  }

  static func registrations(_ output: String) -> [Registration] {
    output.split(separator: "\n").compactMap { line in
      let fields = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
      guard fields.count == 4, UUID(uuidString: fields[1]) != nil, fields[3].hasPrefix("/") else { return nil }
      var heading = fields[0]
      let marker: Character = heading.first.map { "+-!=?".contains($0) ? $0 : " " } ?? " "
      if marker != " " { heading.removeFirst(); heading = heading.trimmingCharacters(in: .whitespaces) }
      let prefix = classID + "("
      guard heading.hasPrefix(prefix), heading.hasSuffix(")") else { return nil }
      let version = String(heading.dropFirst(prefix.count).dropLast())
      guard !version.isEmpty else { return nil }
      return Registration(marker: marker, version: version, url: URL(fileURLWithPath: fields[3]).standardizedFileURL.resolvingSymlinksInPath())
    }
  }

  static func assess(embedded: URL?, driverPresent: Bool, election: String?) -> Assessment {
    let expected = embedded.flatMap(Identity.init)
    func outcome(_ state: String, _ selected: Identity? = nil, _ path: Bool = false, _ version: Bool = false) -> Assessment {
      Assessment(state: state, expected: expected, selected: selected, pathMatches: path, versionMatches: version)
    }
    guard let expected = expected else { return outcome("missing") }
    guard let election = election else { return outcome("unknown") }
    let records = registrations(election)
    guard records.count == 1, let record = records.first else { return outcome("unavailable") }
    let selected = Identity(record.url)
    let samePath = record.url.path == expected.url.path
    let sameVersion = record.version == expected.version && selected?.version == expected.version && selected?.build == expected.build
    if record.version.compare(expected.version, options: .numeric) == .orderedDescending ||
       (record.version == expected.version && selected.map { $0.build.compare(expected.build, options: .numeric) == .orderedDescending } == true) {
      return outcome("host_outdated", selected, samePath, false)
    }
    if !sameVersion { return outcome("version_mismatch", selected, samePath, false) }
    if !samePath { return outcome("path_mismatch", selected, false, true) }
    if record.marker == "-" { return outcome("disabled", selected, true, true) }
    if record.marker == "?" { return outcome("unknown", selected, true, true) }
    if record.marker == "!" || record.marker == "=" { return outcome("unavailable", selected, true, true) }
    return outcome(driverPresent ? "enabled" : "unavailable", selected, true, true)
  }

  static func activate(embedded: URL?, command: ([String]) -> String? = run) -> Bool {
    guard let expected = embedded.flatMap(Identity.init) else { return false }
    // An older host must not silently replace a newer registered component.
    guard let election = command(queryArguments) else { return false }
    for record in registrations(election) {
      if record.version.compare(expected.version, options: .numeric) == .orderedDescending { return false }
      if record.version == expected.version, let selected = Identity(record.url),
         selected.build.compare(expected.build, options: .numeric) == .orderedDescending { return false }
    }
    guard command(["-a", expected.url.path]) != nil else { return false }
    return command(activationArguments) != nil
  }

  static func election() -> String? { run(queryArguments) }

  private static func run(_ arguments: [String]) -> String? {
    let process = Process(), output = Pipe(), done = DispatchSemaphore(value: 0)
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.terminationHandler = { _ in done.signal() }
    do { try process.run() } catch { return nil }
    // Drain concurrently: verbose inventory output must never fill the pipe and
    // block shutdown. Only bounded single-identifier output is accepted.
    let collected = NSMutableData()
    let drained = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .utility).async {
      while true {
        let data = output.fileHandleForReading.availableData
        if data.isEmpty { break }
        if collected.length + data.count <= 1024 * 1024 { collected.append(data) }
      }
      drained.signal()
    }
    guard done.wait(timeout: .now() + 2) == .success else {
      process.terminate()
      return nil
    }
    guard drained.wait(timeout: .now() + 1) == .success, process.terminationStatus == 0 else { return nil }
    return String(data: collected as Data, encoding: .utf8)
  }
}
