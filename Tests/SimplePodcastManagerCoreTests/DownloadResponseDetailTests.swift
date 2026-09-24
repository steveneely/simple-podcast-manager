import Foundation
import Testing
@testable import SimplePodcastManagerCore

struct DownloadResponseDetailTests {
    @Test
    func extractsResultWithoutUnrelatedMetadata() {
        let data = Data(#"{"disclaimer":"Long provider disclaimer","result":"geolocation"}"#.utf8)
        #expect(DownloadResponseDetail.extract(from: data, contentType: "application/json") == "geolocation")
        #expect(DownloadServiceError.requestFailed(statusCode: 403, detail: "geolocation").errorDescription
            == "The episode download failed with HTTP 403. geolocation")
    }

    @Test
    func handlesNestedErrorsAndDeduplicatesMessages() {
        let data = Data(#"{"message":"Unavailable","error":{"message":"Unavailable","reason":"Try later"}}"#.utf8)
        #expect(DownloadResponseDetail.extract(from: data, contentType: "application/json")
            == "Unavailable; Try later")
    }

    @Test
    func normalizesAndLimitsPlainText() {
        let data = Data("  Temporarily\nunavailable\t\r\n".utf8)
        #expect(DownloadResponseDetail.extract(from: data, contentType: "text/plain; charset=utf-8")
            == "Temporarily unavailable")
        let long = Data(String(repeating: "x", count: 20_000).utf8)
        let detail = DownloadResponseDetail.extract(from: long, contentType: "text/plain")
        #expect(detail?.count == 500)
        #expect(detail?.hasSuffix("…") == true)
    }

    @Test
    func omitsUnusableBodiesAndPreservesOriginalStatusMessage() {
        for (data, type) in [
            (Data(), "text/plain"),
            (Data("<html>Forbidden</html>".utf8), "text/plain"),
            (Data("<html>Forbidden</html>".utf8), "text/html"),
            (Data("{broken".utf8), "application/json"),
            (Data([0xff, 0x00]), "application/octet-stream"),
            (Data(#"{"disclaimer":"Not an error explanation"}"#.utf8), "application/json"),
        ] {
            #expect(DownloadResponseDetail.extract(from: data, contentType: type) == nil)
        }
        #expect(DownloadServiceError.requestFailed(statusCode: 403).errorDescription
            == "The episode download failed with HTTP 403.")
    }
}
