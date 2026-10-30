import XCTest
@testable import Bough

final class BoughURLSchemeTests: XCTestCase {

    func testParsesPercentEncodedPath() throws {
        let url = URL(string: "bough://open?path=%2FUsers%2Fme%2Fcode%2Fproj")!
        let request = try BoughURLScheme.parse(url)
        XCTAssertEqual(request.path, "/Users/me/code/proj")
    }

    func testExpandsTilde() throws {
        let url = URL(string: "bough://open?path=%7E%2Fcode")!
        let request = try BoughURLScheme.parse(url)
        XCTAssertFalse(request.path.hasPrefix("~"))
    }

    func testMissingPathThrows() {
        let url = URL(string: "bough://open")!
        XCTAssertThrowsError(try BoughURLScheme.parse(url))
    }

    func testWrongHostThrows() {
        let url = URL(string: "bough://clone?path=/tmp")!
        XCTAssertThrowsError(try BoughURLScheme.parse(url))
    }

    func testEmptyPathThrows() {
        let url = URL(string: "bough://open?path=%20")!
        XCTAssertThrowsError(try BoughURLScheme.parse(url))
    }
}
