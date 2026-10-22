// SPDX-License-Identifier: BSD-3-Clause
import Foundation
let id = WebComponentActivation.classID
let fm = FileManager.default
let temporary = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: temporary) }
func bundle(_ relative: String, version: String = "0.1.13", build: String = "14", executable: Bool = true, identifier: String = id) throws -> URL {
  let root = temporary.appendingPathComponent(relative)
  try fm.createDirectory(at: root.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
  let data: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version,
    "CFBundleVersion": build, "CFBundleExecutable": "CIEPrototypeToken",
    "NSExtension": ["NSExtensionPointIdentifier": "com.apple.ctk-tokens"]]
  try PropertyListSerialization.data(fromPropertyList: data, format: .xml, options: 0).write(to: root.appendingPathComponent("Contents/Info.plist"))
  let binary = root.appendingPathComponent("Contents/MacOS/CIEPrototypeToken")
  try Data([0]).write(to: binary)
  try fm.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: binary.path)
  return root.standardizedFileURL.resolvingSymlinksInPath()
}
func registry(_ url: URL, version: String = "0.1.13", marker: String = "+") -> String {
  "\(marker)    \(id)(\(version))\t\(UUID().uuidString)\t2026-10-22 15:13:39 +0000\t\(url.path)\n (1 plug-in)\n"
}
let expected = try bundle("Firma con CIE è qui.app/Contents/PlugIns/CIEPrototypeToken.appex")
let duplicate = try bundle("Altra copia.app/Contents/PlugIns/CIEPrototypeToken.appex")
let older = try bundle("Old.appex", version: "0.1.12", build: "13")
let otherBuild = try bundle("OldBuild.appex", build: "13")
let newer = try bundle("New.appex", version: "0.1.14", build: "15")
let notExecutable = try bundle("NoExec.appex", executable: false)
let differentID = try bundle("Other.appex", identifier: "other.driver")
let cases: [(URL?, Bool, String?, String)] = [
 (nil, true, registry(expected), "missing"),
 (notExecutable, true, registry(notExecutable), "missing"),
 (differentID, true, registry(differentID), "missing"),
 (expected, true, registry(expected, marker: "-"), "disabled"),
 (expected, false, registry(expected, marker: "-"), "disabled"),
 (expected, true, registry(expected), "enabled"),
 (expected, true, registry(expected, marker: ""), "enabled"),
 (expected, false, registry(expected), "unavailable"),
 (expected, true, registry(expected, marker: "!"), "unavailable"),
 (expected, true, registry(expected, marker: "="), "unavailable"),
 (expected, true, registry(expected, marker: "?"), "unknown"),
 (expected, true, nil, "unknown"),
 (expected, true, "", "unavailable"),
 (expected, true, registry(expected) + registry(duplicate), "unavailable"),
 (expected, true, "+ \(id)(0.1.13)", "unavailable"),
 (expected, true, registry(duplicate), "path_mismatch"),
 (expected, true, registry(older, version: "0.1.12"), "version_mismatch"),
 (expected, true, registry(otherBuild), "version_mismatch"),
 (expected, true, registry(expected, version: "0.1.12"), "version_mismatch"),
 (expected, true, registry(newer, version: "0.1.14"), "host_outdated")
]
for (url, driver, election, state) in cases {
 let assessment = WebComponentActivation.assess(embedded: url, driverPresent: driver, election: election)
 precondition(assessment.state == state, "Expected \(state), got \(assessment.state)")
 // Export only match flags and versions, never a username-bearing file path.
 precondition(!assessment.diagnostics.values.contains { ($0 as? String)?.contains(temporary.path) == true })
}
let alias = temporary.appendingPathComponent("Alias.appex")
try fm.createSymbolicLink(at: alias, withDestinationURL: expected)
precondition(WebComponentActivation.assess(embedded: expected, driverPresent: true, election: registry(alias)).state == "enabled")
var calls = [[String]]()
let fake: ([String]) -> String? = { args in calls.append(args); return args == WebComponentActivation.queryArguments ? registry(duplicate) : "" }
precondition(!WebComponentActivation.activate(embedded: nil, command: fake)); precondition(calls.isEmpty)
precondition(WebComponentActivation.activate(embedded: expected, command: fake))
precondition(calls == [WebComponentActivation.queryArguments, ["-a", expected.path], WebComponentActivation.activationArguments])
precondition(!WebComponentActivation.activate(embedded: expected, command: { _ in nil }))
calls = []
precondition(!WebComponentActivation.activate(embedded: expected, command: { args in calls.append(args); return registry(newer, version: "0.1.14") }))
precondition(calls == [WebComponentActivation.queryArguments])
calls = []
precondition(!WebComponentActivation.activate(embedded: expected, command: { args in calls.append(args); return args == WebComponentActivation.queryArguments ? registry(older, version: "0.1.12") : nil }))
precondition(calls == [WebComponentActivation.queryArguments, ["-a", expected.path]])
print("\(cases.count + 1) component identity/state checks and repair-scope/failure/downgrade checks passed; registry unchanged.")
if CommandLine.arguments.count >= 2 {
 let actual = WebComponentActivation.assess(embedded: URL(fileURLWithPath: CommandLine.arguments[1]), driverPresent: true, election: WebComponentActivation.election())
 print("Mac registry assessment:", actual.state, "pathMatches:", actual.pathMatches, "versionMatches:", actual.versionMatches)
 precondition(actual.state == (CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : "enabled"))
}
