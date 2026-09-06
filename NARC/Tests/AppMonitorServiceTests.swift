import Foundation
import Testing
@testable import NARC

@Test
func dockBadgeReaderUsesDirectBundleResultWhenAvailable() {
    let reader = DockBadgeReader { arguments in
        switch arguments {
        case ["list"]:
            return ""
        case ["info", "-only", "StatusLabel", "com.example.chat"]:
            return #""StatusLabel"={ "label"="7" }"#
        default:
            Issue.record("Unexpected lsappinfo arguments: \(arguments)")
            return nil
        }
    }

    #expect(reader.badgeCount(for: "com.example.chat") == 7)
}

@Test
func dockBadgeReaderReconcilesDirectZeroWithNonzeroDuplicateInstance() {
    let reader = DockBadgeReader { arguments in
        switch arguments {
        case ["list"]:
            return weComLaunchServicesList
        case ["info", "-only", "StatusLabel", "com.tencent.WeWorkMac"]:
            return #""StatusLabel"={ "label"="" }"#
        case ["info", "-only", "StatusLabel", "ASN:0x0-0x12012"]:
            return #""StatusLabel"={ "label"="14" }"#
        case ["info", "-only", "StatusLabel", "ASN:0x0-0x474474"]:
            return #""StatusLabel"=[ NULL ]"#
        default:
            return nil
        }
    }

    #expect(reader.badgeCount(for: "com.tencent.WeWorkMac") == 14)
}

@Test
func dockBadgeReaderUsesLargestValueAcrossDirectAndDuplicateInstances() {
    let reader = DockBadgeReader { arguments in
        switch arguments {
        case ["list"]:
            return weComLaunchServicesList
        case ["info", "-only", "StatusLabel", "com.tencent.WeWorkMac"]:
            return #""StatusLabel"={ "label"="9" }"#
        case ["info", "-only", "StatusLabel", "ASN:0x0-0x12012"]:
            return #""StatusLabel"={ "label"="14" }"#
        case ["info", "-only", "StatusLabel", "ASN:0x0-0x474474"]:
            return #""StatusLabel"={ "label"="" }"#
        default:
            return nil
        }
    }

    #expect(reader.badgeCount(for: "com.tencent.WeWorkMac") == 14)
}

@Test
func dockBadgeReaderFallsBackToDirectValueWhenListIsUnavailable() {
    let reader = DockBadgeReader { arguments in
        switch arguments {
        case ["list"]:
            return nil
        case ["info", "-only", "StatusLabel", "com.example.chat"]:
            return #""StatusLabel"={ "label"="7" }"#
        default:
            return nil
        }
    }

    #expect(reader.badgeCount(for: "com.example.chat") == 7)
}

@Test
func batchBadgeReadListsLaunchServicesOnlyOnce() {
    var listCallCount = 0
    let reader = DockBadgeReader { arguments in
        switch arguments {
        case ["list"]:
            listCallCount += 1
            return weComLaunchServicesList
        case ["info", "-only", "StatusLabel", "com.tencent.WeWorkMac"]:
            return #""StatusLabel"={ "label"="" }"#
        case ["info", "-only", "StatusLabel", "com.example.other"]:
            return #""StatusLabel"={ "label"="2" }"#
        case ["info", "-only", "StatusLabel", "ASN:0x0-0x12012"]:
            return #""StatusLabel"={ "label"="14" }"#
        case ["info", "-only", "StatusLabel", "ASN:0x0-0x474474"]:
            return #""StatusLabel"=[ NULL ]"#
        case ["info", "-only", "StatusLabel", "ASN:0x0-0x999999"]:
            return #""StatusLabel"={ "label"="2" }"#
        default:
            return nil
        }
    }

    let result = reader.badgeCounts(for: ["com.tencent.WeWorkMac", "com.example.other"])
    #expect(result == ["com.tencent.WeWorkMac": 14, "com.example.other": 2])
    #expect(listCallCount == 1)
}

@Test(arguments: [
    (count: 0, uncertain: false, text: Optional<String>.none),
    (count: 14, uncertain: false, text: Optional("14")),
    (count: 120, uncertain: false, text: Optional("99+")),
    (count: 0, uncertain: true, text: Optional("?")),
    (count: 14, uncertain: true, text: Optional("14?")),
])
func badgePresentationNeverDisguisesUnknownAsZero(
    count: Int,
    uncertain: Bool,
    text: String?
) {
    let presentation = BadgePresentation.resolve(
        count: count,
        isUncertain: uncertain
    )
    #expect(presentation.text == text)
    #expect(presentation.isUncertain == uncertain)
}

@Test
func dockBadgeReaderFallsBackToAllMatchingInstancesAndIgnoresNullLabels() {
    let reader = DockBadgeReader { arguments in
        switch arguments {
        case ["info", "-only", "StatusLabel", "com.tencent.WeWorkMac"]:
            return ""
        case ["list"]:
            return weComLaunchServicesList
        case ["info", "-only", "StatusLabel", "ASN:0x0-0x12012"]:
            return #""StatusLabel"={ "label"="14" }"#
        case ["info", "-only", "StatusLabel", "ASN:0x0-0x474474"]:
            return #""StatusLabel"=[ NULL ]"#
        default:
            Issue.record("Unexpected lsappinfo arguments: \(arguments)")
            return nil
        }
    }

    #expect(reader.badgeCount(for: "com.tencent.WeWorkMac") == 14)
}

@Test
func dockBadgeReaderTreatsAnExplicitEmptyLabelAsZero() {
    let reader = DockBadgeReader { _ in
        #""StatusLabel"={ "label"="" }"#
    }

    #expect(reader.badgeCount(for: "com.example.chat") == 0)
}

@Test
func dockBadgeReaderUsesLargestInstanceValueWithoutAddingDuplicates() {
    let reader = DockBadgeReader { arguments in
        switch arguments {
        case ["info", "-only", "StatusLabel", "com.tencent.WeWorkMac"]:
            return nil
        case ["list"]:
            return weComLaunchServicesList
        case ["info", "-only", "StatusLabel", "ASN:0x0-0x12012"]:
            return #""StatusLabel"={ "label"="14" }"#
        case ["info", "-only", "StatusLabel", "ASN:0x0-0x474474"]:
            return #""StatusLabel"={ "label"="9" }"#
        default:
            return nil
        }
    }

    #expect(reader.badgeCount(for: "com.tencent.WeWorkMac") == 14)
}

@Test
func dockBadgeReaderReturnsNilWhenLaunchServicesCannotProvideAValue() {
    let reader = DockBadgeReader { arguments in
        arguments == ["list"] ? "" : nil
    }

    #expect(reader.badgeCount(for: "com.example.chat") == nil)
}

@Test
func dockBadgeReaderTreatsNonNumericLabelsAsUnknown() {
    let reader = DockBadgeReader { arguments in
        switch arguments {
        case ["list"]:
            return ""
        case ["info", "-only", "StatusLabel", "com.example.chat"]:
            return #""StatusLabel"={ "label"="new" }"#
        default:
            return nil
        }
    }

    #expect(reader.badgeCount(for: "com.example.chat") == nil)
}

@Test
func dockBadgeReaderTreatsNegativeLabelsAsUnknown() {
    let reader = DockBadgeReader { arguments in
        switch arguments {
        case ["list"]:
            return ""
        case ["info", "-only", "StatusLabel", "com.example.chat"]:
            return #""StatusLabel"={ "label"="-3" }"#
        default:
            return nil
        }
    }

    #expect(reader.badgeCount(for: "com.example.chat") == nil)
}

@Test
func dockBadgeReaderDoesNotLetDirectZeroHideNonNumericInstance() {
    let reader = DockBadgeReader { arguments in
        switch arguments {
        case ["list"]:
            return weComLaunchServicesList
        case ["info", "-only", "StatusLabel", "com.tencent.WeWorkMac"]:
            return #""StatusLabel"={ "label"="" }"#
        case ["info", "-only", "StatusLabel", "ASN:0x0-0x12012"]:
            return #""StatusLabel"={ "label"="99+" }"#
        case ["info", "-only", "StatusLabel", "ASN:0x0-0x474474"]:
            return #""StatusLabel"=[ NULL ]"#
        default:
            return nil
        }
    }

    #expect(reader.badgeCount(for: "com.tencent.WeWorkMac") == nil)
}

@Test
func dockBadgeReaderDoesNotLetDirectZeroHideNegativeInstance() {
    let reader = DockBadgeReader { arguments in
        switch arguments {
        case ["list"]:
            return weComLaunchServicesList
        case ["info", "-only", "StatusLabel", "com.tencent.WeWorkMac"]:
            return #""StatusLabel"={ "label"="" }"#
        case ["info", "-only", "StatusLabel", "ASN:0x0-0x12012"]:
            return #""StatusLabel"={ "label"="-3" }"#
        case ["info", "-only", "StatusLabel", "ASN:0x0-0x474474"]:
            return #""StatusLabel"=[ NULL ]"#
        default:
            return nil
        }
    }

    #expect(reader.badgeCount(for: "com.tencent.WeWorkMac") == nil)
}

@Test
func badgeStatusIsUncertainOnlyWhenARunningEnabledAppHasNoValue() {
    let running: Set<String> = ["com.example.chat", "com.tencent.WeWorkMac"]

    #expect(AppMonitorService.badgeStatusIsUncertain(
        enabledRunningBundleIDs: running,
        badgeMap: ["com.example.chat": 2]
    ))
    #expect(!AppMonitorService.badgeStatusIsUncertain(
        enabledRunningBundleIDs: running,
        badgeMap: ["com.example.chat": 2, "com.tencent.WeWorkMac": 14]
    ))
    #expect(!AppMonitorService.badgeStatusIsUncertain(
        enabledRunningBundleIDs: [],
        badgeMap: [:]
    ))
}

@Test
func processRunnerDrainsOutputLargerThanThePipeBuffer() {
    let output = DockBadgeReader.runProcess(
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "/usr/bin/yes x | /usr/bin/head -c 262144"]
    )

    #expect(output?.utf8.count == 262_144)
}

private let weComLaunchServicesList = #"""
 7) "企业微信" ASN:0x0-0x12012:
    bundleID="com.tencent.WeWorkMac"
    bundle path="/Applications/企业微信.app"
 103) "企业微信" ASN:0x0-0x474474:
    bundleID="com.tencent.WeWorkMac"
    bundle path="/Applications/企业微信.app"
 104) "Other" ASN:0x0-0x999999:
    bundleID="com.example.other"
"""#
