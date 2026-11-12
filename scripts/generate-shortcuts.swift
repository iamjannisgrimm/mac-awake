import Foundation

// The same two actions as the original shortcuts, with the script embedded so
// administrator execution never depends on a particular username or home folder.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let destination = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for mode in ["On", "Off"] {
    let script = try String(contentsOf: root.appendingPathComponent("scripts/Keep-Mac-Awake-\(mode.uppercased()).command"), encoding: .utf8)
    let actionID = mode == "On" ? "145638E1-3A18-45AB-9509-1386F55C8ED8" : "D7060351-285F-40FB-AF46-9E3DBF442726"
    let workflow: [String: Any] = [
        "WFWorkflowName": "Keep Mac Awake \(mode)",
        "WFWorkflowClientVersion": "2600",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": ["WFWorkflowIconGlyphNumber": 61440, "WFWorkflowIconStartColor": 1440408063],
        "WFWorkflowTypes": ["WFWorkflowTypeShowInSearch"],
        "WFQuickActionSurfaces": [],
        "WFWorkflowImportQuestions": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowOutputContentItemClasses": ["WFGenericFileContentItem"],
        "WFWorkflowHasOutputFallback": false,
        "WFWorkflowHasShortcutInputVariables": false,
        "WFWorkflowActions": [
            ["WFWorkflowActionIdentifier": "is.workflow.actions.runshellscript",
             "WFWorkflowActionParameters": ["RunAsRoot": true, "Shell": "/bin/zsh", "Script": script, "UUID": actionID]],
            ["WFWorkflowActionIdentifier": "is.workflow.actions.output",
             "WFWorkflowActionParameters": ["WFOutput": ["WFSerializationType": "WFTextTokenString", "Value": [
                "string": "\u{fffc}", "attachmentsByRange": ["{0, 1}": [
                    "OutputName": "Shell Script Result", "OutputUUID": actionID, "Type": "ActionOutput"]]]]]]
        ]
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: workflow, format: .xml, options: 0)
    try data.write(to: destination.appendingPathComponent("Keep Mac Awake \(mode).plist"))
}
