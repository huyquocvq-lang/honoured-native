import XCTest

final class WebCredentialTests: XCTestCase {
    func testTrimsTheEmailAndKeepsThePasswordExactly() {
        let credential = WebCredential.parse(["email": "  ann@example.com\n", "password": " Pa ss "])
        XCTAssertEqual(credential, WebCredential(email: "ann@example.com", password: " Pa ss "))
    }

    func testRefusesMissingEmptyOrNonStringFields() {
        XCTAssertNil(WebCredential.parse([:]))
        XCTAssertNil(WebCredential.parse(["email": "ann@example.com"]))
        XCTAssertNil(WebCredential.parse(["password": "secret"]))
        XCTAssertNil(WebCredential.parse(["email": "   ", "password": "secret"]))
        XCTAssertNil(WebCredential.parse(["email": "ann@example.com", "password": ""]))
        XCTAssertNil(WebCredential.parse(["email": "ann", "password": "secret"]), "an email needs an @")
        XCTAssertNil(WebCredential.parse(["email": 42, "password": "secret"]))
        XCTAssertNil(WebCredential.parse(["email": "ann@example.com", "password": NSNumber(value: 1234)]))
        XCTAssertNil(WebCredential.parse(["email": NSNull(), "password": "secret"]))
    }

    func testRefusesOversizedValues() {
        let longEmail = String(repeating: "a", count: WebCredential.maxEmailLength) + "@x"
        XCTAssertNil(WebCredential.parse(["email": longEmail, "password": "secret"]))
        let longPassword = String(repeating: "p", count: WebCredential.maxPasswordLength + 1)
        XCTAssertNil(WebCredential.parse(["email": "ann@example.com", "password": longPassword]))
        let maxPassword = String(repeating: "p", count: WebCredential.maxPasswordLength)
        XCTAssertNotNil(WebCredential.parse(["email": "ann@example.com", "password": maxPassword]))
    }

    func testSavingIsOfferedOnlyForTheAssociatedHTTPSHost() {
        let web = URL(string: "https://honour-your-word.lovable.app")
        XCTAssertTrue(WebCredential.isSupported(associatedHost: "honour-your-word.lovable.app", webAppURL: web))
        XCTAssertTrue(WebCredential.isSupported(associatedHost: "Honour-Your-Word.lovable.app", webAppURL: web))
        XCTAssertFalse(WebCredential.isSupported(associatedHost: "", webAppURL: web), "no associated domain in this build")
        XCTAssertFalse(WebCredential.isSupported(associatedHost: "$(HONOURED_WEB_HOST)", webAppURL: web), "an unexpanded build setting")
        XCTAssertFalse(WebCredential.isSupported(associatedHost: "honoured.app", webAppURL: web), "another domain")
        XCTAssertFalse(WebCredential.isSupported(associatedHost: "localhost", webAppURL: URL(string: "http://localhost:3000")))
        XCTAssertFalse(WebCredential.isSupported(associatedHost: "honour-your-word.lovable.app", webAppURL: nil))
    }
}
