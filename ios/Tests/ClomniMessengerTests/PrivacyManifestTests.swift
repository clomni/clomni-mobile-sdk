import Foundation
import XCTest
@testable import ClomniMessenger

/// ios/Sources/ClomniMessenger/PrivacyInfo.xcprivacy: a valid privacy manifest, shipped as the SwiftPM target's
/// resource, whose required-reason APIs are exactly the ones the sources call.
final class PrivacyManifestTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func manifest() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("ios/Sources/ClomniMessenger/PrivacyInfo.xcprivacy"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// Apple's identifiers (developer.apple.com, "Describing data use in privacy manifests").
    private static let dataTypes: Set<String> = [
        "Name", "EmailAddress", "PhoneNumber", "PhysicalAddress", "OtherUserContactInfo", "Health", "Fitness",
        "PaymentInfo", "CreditInfo", "OtherFinancialInfo", "PreciseLocation", "CoarseLocation", "SensitiveInfo",
        "Contacts", "EmailsOrTextMessages", "PhotosorVideos", "AudioData", "GameplayContent", "CustomerSupport",
        "OtherUserContent", "BrowsingHistory", "SearchHistory", "UserID", "DeviceID", "PurchaseHistory",
        "ProductInteraction", "AdvertisingData", "OtherUsageData", "CrashData", "PerformanceData",
        "OtherDiagnosticData", "EnvironmentScanning", "Hands", "Head", "OtherDataTypes",
    ]
    private static let purposes: Set<String> = [
        "ThirdPartyAdvertising", "DeveloperAdvertising", "Analytics", "ProductPersonalization", "AppFunctionality", "Other",
    ]

    func testWhatIsCollected() throws {
        let manifest = try manifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        var types: [String] = []
        for entry in collected {
            let type = try XCTUnwrap(entry["NSPrivacyCollectedDataType"] as? String)
            XCTAssertTrue(type.hasPrefix("NSPrivacyCollectedDataType"))
            XCTAssertTrue(Self.dataTypes.contains(String(type.dropFirst("NSPrivacyCollectedDataType".count))), type)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, true, type)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false, type)
            let purposes = try XCTUnwrap(entry["NSPrivacyCollectedDataTypePurposes"] as? [String])
            XCTAssertEqual(purposes, ["NSPrivacyCollectedDataTypePurposeAppFunctionality"], type)
            XCTAssertTrue(purposes.allSatisfy { Self.purposes.contains(String($0.dropFirst("NSPrivacyCollectedDataTypePurpose".count))) })
            types.append(type)
        }
        XCTAssertEqual(types.map { String($0.dropFirst("NSPrivacyCollectedDataType".count)) }, [
            "DeviceID", "UserID", "Name", "EmailAddress", "PhoneNumber", "CustomerSupport", "PhotosorVideos",
            "OtherUserContent", "ProductInteraction",
        ])
        XCTAssertFalse(types.contains("NSPrivacyCollectedDataTypeCrashData"))
    }

    /// The "required reason" APIs and how a call to each looks in Swift.
    private static let reasonAPIs: [String: [String]] = [
        "NSPrivacyAccessedAPICategoryUserDefaults": [#"\bUserDefaults\b"#, #"@AppStorage\b"#],
        "NSPrivacyAccessedAPICategoryFileTimestamp": [
            #"\.creationDate\b"#, #"\.modificationDate\b"#, #"fileModificationDate"#, #"contentModificationDateKey"#,
            #"creationDateKey"#, #"\b(f|l)?stat(at)?\s*\("#, #"\b(f)?getattrlist(bulk|at)?\s*\("#,
        ],
        "NSPrivacyAccessedAPICategorySystemBootTime": [#"systemUptime"#, #"mach_absolute_time"#],
        "NSPrivacyAccessedAPICategoryDiskSpace": [
            #"volume\w*CapacityKey"#, #"systemFreeSize"#, #"\bsystemSize\b"#, #"\bf?statv?fs\s*\("#,
        ],
        "NSPrivacyAccessedAPICategoryActiveKeyboards": [#"activeInputModes"#],
    ]

    private func categoriesCalled(in source: String) -> Set<String> {
        let code = source.components(separatedBy: "\n")
            .map { line in line.range(of: #"(^|\s)//.*$"#, options: .regularExpression).map { String(line[..<$0.lowerBound]) } ?? line }
            .joined(separator: "\n")
        return Set(Self.reasonAPIs.filter { _, patterns in
            patterns.contains { code.range(of: $0, options: .regularExpression) != nil }
        }.keys)
    }

    func testTheRequiredReasonAPIsAreTheOnesCalled() throws {
        let sources = root.appendingPathComponent("ios/Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(atPath: sources.path)).compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") }
        XCTAssertGreaterThan(files.count, 30)
        var called = Set<String>()
        for file in files {
            called.formUnion(categoriesCalled(in: try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)))
        }
        let declared = try XCTUnwrap(try manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        for entry in declared {
            XCTAssertFalse((entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []).isEmpty, "\(entry)")
        }
        XCTAssertEqual(Set(declared.compactMap { $0["NSPrivacyAccessedAPIType"] as? String }), called,
                       "declare each category the sources call, with its reason, in PrivacyInfo.xcprivacy")
    }

    func testTheScannerFindsCalls() {
        XCTAssertEqual(categoriesCalled(in: "let x = UserDefaults.standard.bool(forKey: \"a\")"),
                       ["NSPrivacyAccessedAPICategoryUserDefaults"])
        XCTAssertEqual(categoriesCalled(in: "let a = try FileManager.default.attributesOfItem(atPath: p)[.modificationDate]"),
                       ["NSPrivacyAccessedAPICategoryFileTimestamp"])
        XCTAssertEqual(categoriesCalled(in: "let up = ProcessInfo.processInfo.systemUptime"),
                       ["NSPrivacyAccessedAPICategorySystemBootTime"])
        XCTAssertEqual(categoriesCalled(in: "let v = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])"),
                       ["NSPrivacyAccessedAPICategoryDiskSpace"])
        XCTAssertEqual(categoriesCalled(in: "// UserDefaults in a comment\nlet status = stats(1)"), [])
    }

    /// SwiftPM ships it with the ClomniMessenger target (CocoaPods: the ClomniMessenger_Privacy bundle).
    func testItShipsAsAResource() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        XCTAssertEqual(try Data(contentsOf: url),
                       try Data(contentsOf: root.appendingPathComponent("ios/Sources/ClomniMessenger/PrivacyInfo.xcprivacy")))
        let podspec = try String(contentsOf: root.appendingPathComponent("ClomniMessenger.podspec"), encoding: .utf8)
        XCTAssertTrue(podspec.contains("'ios/Sources/ClomniMessenger/PrivacyInfo.xcprivacy'"))
    }
}
