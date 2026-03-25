import XCTest

final class YTDLPGUIUITests: XCTestCase {
    @MainActor
    func testLibrarySupportsListAndGalleryViews() throws {
        continueAfterFailure = false

        let libraryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: libraryURL) }

        FileManager.default.createFile(
            atPath: libraryURL.appendingPathComponent("sample-1.mp4").path,
            contents: Data("video".utf8)
        )
        FileManager.default.createFile(
            atPath: libraryURL.appendingPathComponent("sample-2.webm").path,
            contents: Data("video".utf8)
        )
        FileManager.default.createFile(
            atPath: libraryURL.appendingPathComponent("sample-3.m4a").path,
            contents: Data("audio".utf8)
        )

        let app = XCUIApplication()
        app.launchEnvironment["YTDLPGUI_UI_TEST_LIBRARY_PATH"] = libraryURL.path
        app.launchEnvironment["YTDLPGUI_UI_TEST_INITIAL_SECTION"] = "library"
        app.launch()

        XCTAssertTrue(app.staticTexts["Saved Media"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.listRow.sample-1.mp4"].waitForExistence(timeout: 5))

        let segmentedControl = app.segmentedControls["library.viewPicker"]
        XCTAssertTrue(segmentedControl.waitForExistence(timeout: 5))

        segmentedControl.buttons["Gallery"].click()

        XCTAssertTrue(app.buttons["library.galleryItem.sample-1.mp4"].waitForExistence(timeout: 5))

        segmentedControl.buttons["List"].click()

        XCTAssertTrue(app.buttons["library.listRow.sample-2.webm"].waitForExistence(timeout: 5))
    }
}
