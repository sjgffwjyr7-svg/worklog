import XCTest
@testable import MyApp

final class MyAppTests: XCTestCase {
    func testDemoTabDefaultsToFirst() { XCTAssertEqual(DemoMode.initialTab, 0) }
}
