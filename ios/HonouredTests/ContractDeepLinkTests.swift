import XCTest

final class ContractDeepLinkTests: XCTestCase {
    private let token = "7C9D2B8E-3F0A-4F43-9A56-0D2E9B1C4A77"

    func testRoundTripKeepsAnOpaqueContractId() throws {
        let target = ContractDeepLink.Target(contractId: "k3j4 x/y?z#1%", healthDay: "2026-09-23", occurrenceToken: token)
        let url = try XCTUnwrap(ContractDeepLink.url(for: target))
        XCTAssertEqual(url.scheme, "honoured")
        XCTAssertEqual(url.host, "contract")
        XCTAssertEqual(ContractDeepLink.parse(url), target)
    }

    func testRejectsAnythingThatIsNotExactlyAContractLink() {
        let valid = "honoured://contract/c-walk?day=2026-09-23&occurrence=\(token)"
        XCTAssertNotNil(ContractDeepLink.parse(URL(string: valid)!))
        let invalid = [
            "https://contract/c-walk?day=2026-09-23&occurrence=\(token)",
            "honoured://settings/c-walk?day=2026-09-23&occurrence=\(token)",
            "honoured://contract/c-walk/extra?day=2026-09-23&occurrence=\(token)",
            "honoured://contract/?day=2026-09-23&occurrence=\(token)",
            "honoured://contract/c-walk?day=2026-13-40&occurrence=\(token)",
            "honoured://contract/c-walk?day=2026-09-23&occurrence=not-a-token",
            "honoured://contract/c-walk?day=2026-09-23",
            "honoured://contract/c-walk?day=2026-09-23&occurrence=\(token)&day=2026-09-24",
            "honoured://contract/c-walk?day=2026-09-23&occurrence=\(token)&token=secret",
            "honoured://user:pass@contract/c-walk?day=2026-09-23&occurrence=\(token)",
            "honoured://contract/c-walk?day=2026-09-23&occurrence=\(token)#fragment"
        ]
        for string in invalid {
            XCTAssertNil(URL(string: string).flatMap(ContractDeepLink.parse), string)
        }
    }

    func testIdentifiersAreBoundedAndPrintable() {
        XCTAssertTrue(HonouredIdentifiers.isValidIdentifier("c-1:primary"))
        XCTAssertFalse(HonouredIdentifiers.isValidIdentifier(""))
        XCTAssertFalse(HonouredIdentifiers.isValidIdentifier("   "))
        XCTAssertFalse(HonouredIdentifiers.isValidIdentifier("a\nb"))
        XCTAssertFalse(HonouredIdentifiers.isValidIdentifier(String(repeating: "x", count: 129)))
        XCTAssertTrue(HonouredIdentifiers.isValidHealthDay("2024-02-29"))
        XCTAssertFalse(HonouredIdentifiers.isValidHealthDay("2026-02-29"))
        XCTAssertFalse(HonouredIdentifiers.isValidHealthDay("2026-9-23"))
    }
}
