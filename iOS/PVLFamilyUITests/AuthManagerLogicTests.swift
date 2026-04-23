import XCTest
@testable import PVLFamily

final class AuthManagerLogicTests: XCTestCase {
    func testResolvedBaseURLForLocal() {
        XCTAssertEqual(AuthManager.resolvedBaseURL(for: .local), "http://127.0.0.1:8000")
    }

    func testResolvedBaseURLForCloud() {
        XCTAssertEqual(AuthManager.resolvedBaseURL(for: .cloud), "https://pvlfamily.ru")
    }

    func testAPIErrorMessageFromDetailJSON() {
        let data = #"{"detail":"Неверный токен"}"#.data(using: .utf8)
        XCTAssertEqual(AuthManager.apiErrorMessage(from: data), "Неверный токен")
    }

    func testAPIErrorMessageFromPlainText() {
        let data = "Server exploded".data(using: .utf8)
        XCTAssertEqual(AuthManager.apiErrorMessage(from: data), "Server exploded")
    }
}
