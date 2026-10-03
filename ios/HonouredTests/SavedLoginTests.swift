import XCTest

final class SavedLoginTests: XCTestCase {
    func testTrimsTheEmailAndKeepsThePasswordExactly() {
        let login = SavedLogin.parse(["email": "  ann@example.com\n", "password": " Pa ss "])
        XCTAssertEqual(login, SavedLogin(email: "ann@example.com", password: " Pa ss "))
    }

    func testRefusesMissingEmptyOrNonStringFields() {
        XCTAssertNil(SavedLogin.parse([:]))
        XCTAssertNil(SavedLogin.parse(["email": "ann@example.com"]))
        XCTAssertNil(SavedLogin.parse(["password": "secret"]))
        XCTAssertNil(SavedLogin.parse(["email": "   ", "password": "secret"]))
        XCTAssertNil(SavedLogin.parse(["email": "ann@example.com", "password": ""]))
        XCTAssertNil(SavedLogin.parse(["email": "ann", "password": "secret"]), "an email needs an @")
        XCTAssertNil(SavedLogin.parse(["email": 42, "password": "secret"]))
        XCTAssertNil(SavedLogin.parse(["email": "ann@example.com", "password": NSNumber(value: 1234)]))
        XCTAssertNil(SavedLogin.parse(["email": NSNull(), "password": "secret"]))
    }

    func testRefusesOversizedValues() {
        let longEmail = String(repeating: "a", count: SavedLogin.maxEmailLength) + "@x"
        XCTAssertNil(SavedLogin.parse(["email": longEmail, "password": "secret"]))
        let longPassword = String(repeating: "p", count: SavedLogin.maxPasswordLength + 1)
        XCTAssertNil(SavedLogin.parse(["email": "ann@example.com", "password": longPassword]))
        let maxPassword = String(repeating: "p", count: SavedLogin.maxPasswordLength)
        XCTAssertNotNil(SavedLogin.parse(["email": "ann@example.com", "password": maxPassword]))
    }

    func testReplyPayloadSaysWhetherALoginIsStored() {
        XCTAssertEqual(SavedLogin.replyPayload(nil) as NSDictionary, ["found": false] as NSDictionary)
        let stored = SavedLogin(email: "ann@example.com", password: "secret")
        XCTAssertEqual(
            SavedLogin.replyPayload(stored) as NSDictionary,
            ["found": true, "email": "ann@example.com", "password": "secret"] as NSDictionary
        )
    }

    func testRoundTripsThroughTheStoredEncoding() throws {
        let login = SavedLogin(email: "ann@example.com", password: "p\"w✓")
        let data = try JSONEncoder().encode(login)
        XCTAssertEqual(try JSONDecoder().decode(SavedLogin.self, from: data), login)
    }
}
