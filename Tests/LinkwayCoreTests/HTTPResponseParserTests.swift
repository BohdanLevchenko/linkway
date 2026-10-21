import Foundation
import Testing
@testable import LinkwayCore

@Test(arguments: [301, 302, 303, 307, 308, 200, 405, 501])
func parsesHTTPStatus(status: Int) throws {
    let response = try #require(try HTTPResponseParser.parse(Data("HTTP/1.1 \(status) Status\r\nLocation: /next?q=1\r\n\r\nbody".utf8)))
    #expect(response.status == status)
    #expect(response.location == "/next?q=1")
}

@Test func lowercaseLocationAndMissingLocation() throws {
    #expect(try HTTPResponseParser.parse(Data("HTTP/1.0 302 Found\r\nlocation:  https://example.com/ \t\r\n\r\n".utf8))?.location == "https://example.com/")
    let response = try #require(try HTTPResponseParser.parse(Data("HTTP/1.1 405 Nope\r\nContent-Length: 0\r\n\r\n".utf8)))
    #expect(response.status == 405)
    #expect(response.location == nil)
    #expect(try HTTPResponseParser.parse(Data("HTTP/1.1 302 Found\r\nLoc".utf8)) == nil)
}

@Test func headerSizeLimit() throws {
    let prefix = "HTTP/1.1 302 Found\r\nX-Pad: "
    let suffix = "\r\n\r\n"
    let exact = prefix + String(repeating: "a", count: HTTPResponseParser.maximumHeaderBytes - prefix.utf8.count - suffix.utf8.count) + suffix
    #expect(try HTTPResponseParser.parse(Data(exact.utf8))?.status == 302)
    #expect(throws: ResolveFailure.network) { try HTTPResponseParser.parse(Data(("HTTP/1.1 302 Found\r\nX-Pad: a" + exact.dropFirst(prefix.count)).utf8)) }
    #expect(throws: ResolveFailure.network) { try HTTPResponseParser.parse(Data(repeating: 97, count: HTTPResponseParser.maximumHeaderBytes)) }
    #expect(try HTTPResponseParser.parse(Data((exact + String(repeating: "b", count: 20000)).utf8))?.status == 302)
}

@Test(arguments: ["garbage\r\n\r\n", "HTTP/2 302 Found\r\n\r\n", "HTTP/1.1 xyz Found\r\n\r\n",
                  "HTTP/1.1 99 Bad\r\n\r\n", "HTTP/1.1 700 Bad\r\n\r\n", "HTTP/1.1 302 Found\r\nBroken\r\n\r\n",
                  "HTTP/1.1 302 Found\r\nLocation: /one\r\n /two\r\n\r\n",
                  "HTTP/1.1 302 Found\r\nLocation: /one\r\nlocation: /two\r\n\r\n"])
func rejectsGarbageHeaders(text: String) {
    #expect(throws: ResolveFailure.network) { try HTTPResponseParser.parse(Data(text.utf8)) }
}
