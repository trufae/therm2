import AppKit
import Testing
@testable import Therm2

@Suite(.serialized) @MainActor
struct UpdateCheckerTests {
    init() { _ = NSApplication.shared }

    private final class ReleaseProtocol: URLProtocol, @unchecked Sendable {
        // This serialized suite changes the reply only between completed requests.
        nonisolated(unsafe) static var reply: Result<(Int, String), URLError> = .success((200, "{}"))

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            #expect(request.url?.absoluteString == "https://api.github.com/repos/trufae/therm2/releases/latest")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
            switch Self.reply {
            case .success(let (status, json)):
                let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                               httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(json.utf8))
                client?.urlProtocolDidFinishLoading(self)
            case .failure(let error):
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        override func stopLoading() {}
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test(arguments: [
        (200, #"{"tag_name":"0.4.0"}"#, "0.4.0" as String?),
        (200, #"{"tag_name":"0.2.0"}"#, "0.2.0"),
        (200, #"{"tag_name":"v0.3.0"}"#, "v0.3.0"),
        (200, #"{"tag_name":"0.3.0"}"#, nil),
        (200, #"{"tag_name":""}"#, nil),
        (200, #"{"tag_name":" \n"}"#, nil),
        (200, #"{"tag_name":null}"#, nil),
        (200, #"{"tag_name":42}"#, nil),
        (200, "{}", nil),
        (200, "not JSON", nil),
        (403, #"{"message":"API rate limit exceeded"}"#, nil),
        (404, #"{"message":"Not Found"}"#, nil),
        (500, #"{"tag_name":"0.4.0"}"#, nil)
    ])
    func checksDifferentTagsAndIgnoresInvalidResponses(status: Int, json: String, expected: String?) async {
        ReleaseProtocol.reply = .success((status, json))
        let session = session()
        defer { session.invalidateAndCancel() }
        #expect(await UpdateChecker.availableVersion(currentVersion: "0.3.0", session: session) == expected)
    }

    @Test func networkFailureIsSilent() async {
        ReleaseProtocol.reply = .failure(URLError(.notConnectedToInternet))
        let session = session()
        defer { session.invalidateAndCancel() }
        #expect(await UpdateChecker.availableVersion(currentVersion: "0.3.0", session: session) == nil)
    }

    @Test func dialogShowsBothVersionsAndOffersReleasesOrCancel() {
        let alert = UpdateChecker.makeAlert(currentVersion: "0.3.0", upstreamVersion: "0.4.0")
        #expect(alert.informativeText == "Current version: 0.3.0\nLatest release: 0.4.0")
        #expect(alert.buttons.map(\.title) == ["Open Releases", "Cancel"])
        #expect(UpdateChecker.releasesURL.absoluteString == "https://github.com/trufae/therm2/releases")
    }
}
