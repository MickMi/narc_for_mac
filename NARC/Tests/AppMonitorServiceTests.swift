import Foundation
import Testing
@testable import NARC

@Test
func dockBadgeReaderUsesDirectBundleResultWhenAvailable() {
    let reader = DockBadgeReader { arguments in
        #expect(arguments == ["info", "-only", "StatusLabel", "com.example.chat"])
        return #""StatusLabel"={ "label"="7" }"#
    }

    #expect(reader.badgeCount(for: "com.example.chat") == 7)
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
