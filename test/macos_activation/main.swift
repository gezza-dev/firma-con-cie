// SPDX-License-Identifier: BSD-3-Clause
import Foundation
let id = WebComponentActivation.classID
let cases: [(Bool, Bool, String?, String)] = [
 (false, true, "+ \(id)(1)", "missing"),
 (true, true, "- \(id)(1)", "disabled"),
 (true, false, "- \(id)(1)", "disabled"),
 (true, true, "+ \(id)(1)", "enabled"),
 (true, true, "  \(id)(1)", "enabled"),
 (true, false, "+ \(id)(1)", "unavailable"),
 (true, true, "! \(id)(1)", "unavailable"),
 (true, true, "= \(id)(1)", "unavailable"),
 (true, true, "? \(id)(1)", "unknown"),
 (true, true, nil, "unknown"),
 (true, true, "+ other.id(1)", "unavailable"),
 (true, true, "", "unavailable"),
 (true, true, "+ \(id)(1)\n- \(id)(2)", "unavailable")
]
for (bundled, driver, election, expected) in cases {
 precondition(WebComponentActivation.state(bundled: bundled, driverPresent: driver, election: election) == expected)
}
print("13 activation state checks passed; read-only registry query:", WebComponentActivation.election() != nil)

var calls = [[String]]()
let fake: ([String]) -> String? = { args in calls.append(args); return "" }
precondition(!WebComponentActivation.activate(bundled: false, command: fake))
precondition(calls.isEmpty)
precondition(WebComponentActivation.activate(bundled: true, command: fake))
precondition(calls == [["-e", "use", "-i", id, "-p", "com.apple.ctk-tokens"]])
precondition(!WebComponentActivation.activate(bundled: true, command: { _ in nil }))
print("Activation command scope/failure checks passed; no election changed by tests")
