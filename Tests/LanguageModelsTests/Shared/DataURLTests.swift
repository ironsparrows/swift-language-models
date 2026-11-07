import Foundation
import LanguageModels
import Testing

@Suite("Data URL")
struct DataURLTests {
    @Test func `bytes become a base64 data URL of their media type`() {
        #expect(DataURL(mediaType: "application/pdf", data: Data("%PDF".utf8)).text == "data:application/pdf;base64,JVBERg==")
    }

    @Test func `a base64 data URL is read back, without its parameters`() throws {
        let url = try #require(DataURL("data:image/png;charset=binary;base64,iVBORw=="))

        #expect(url.mediaType == "image/png")
        #expect(url.data == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test(arguments: [
        "https://example.com/cat.png", "data:text/plain,hello", "data:image/png;base64", "data:base64,aGk=",
        "data:image/png;base64,not base64!",
    ])
    func `anything but a base64 data URL is refused`(text: String) {
        #expect(DataURL(text) == nil)
    }
}
