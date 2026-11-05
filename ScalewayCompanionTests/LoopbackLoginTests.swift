// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ScalewayCompanion

@MainActor
final class LoopbackLoginTests: XCTestCase {
    private func request(_ attempt: LoginAttempt, target: String? = nil, host: String? = nil, method: String = "GET") -> Data {
        Data("\(method) \(target ?? attempt.callbackURL.path) HTTP/1.1\r\nHost: \(host ?? "localhost:\(attempt.port)")\r\n\r\n".utf8)
    }
    func testHTTPBoundaryRejectsForeignHostsMethodsBodiesAndPaths() throws {
        let attempt = LoginAttempt(port: 34567)
        for data in [request(attempt, host: "evil.example"), request(attempt, method: "POST"), request(attempt, target: "http://evil.example/"), request(attempt, target: "/old/callback"), request(attempt) + Data("body".utf8)] {
            XCTAssertThrowsError(try attempt.decodeRequest(data))
        }
        XCTAssertNil(try attempt.decodeRequest(Data("GET / HTTP/1.1\r\n".utf8)))
    }
    func testRealLoopbackHandoffRejectsUnrelatedRequestThenAcceptsOnce() async throws {
        let receiver = LoopbackCallback()
        let attempt = try await receiver.start()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel(); receiver.cancel() }
        let (_, badResponse) = try await session.data(from: URL(string: "http://localhost:\(attempt.port)/wrong")!)
        XCTAssertEqual((badResponse as? HTTPURLResponse)?.statusCode, 400)
        XCTAssertFalse(receiver.isClosed)
        let object: [String: Any] = ["token": "test.jwt.signature", "renewToken": "discard-me", "jwt": ["jti": UUID().uuidString, "audienceId": UUID().uuidString]]
        var url = URLComponents(url: attempt.callbackURL, resolvingAgainstBaseURL: false)!
        url.queryItems = [.init(name: "token", value: try JSONSerialization.data(withJSONObject: object).base64EncodedString())]
        let (body, response) = try await session.data(from: url.url!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("signature"))
        // Browser dismissal can be delivered before the suspended consumer resumes.
        let handoff = LoginHandoff()
        XCTAssertTrue(receiver.callbackAccepted)
        XCTAssertFalse(handoff.shouldCancelForBrowserDismissal(callbackAccepted: receiver.callbackAccepted))
        let envelope = try await receiver.wait()
        XCTAssertEqual(envelope.token, "test.jwt.signature")
        XCTAssertTrue(receiver.isClosed)
        do { _ = try await receiver.wait(); XCTFail("Callback consumed twice") } catch { }
        do { _ = try await session.data(from: url.url!); XCTFail("Listener still open") } catch { }
    }
    func testTaskCancellationDuringWaitCleansUp() async throws {
        let receiver = LoopbackCallback()
        _ = try await receiver.start()
        let task = Task { try await receiver.wait() }
        await Task.yield()
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation ignored") } catch { }
        await Task.yield()
        XCTAssertTrue(receiver.isClosed)
    }
    func testCancellationClosesListenerAndWaiter() async throws {
        let receiver = LoopbackCallback()
        _ = try await receiver.start()
        let waiter = Task { try await receiver.wait() }
        receiver.cancel()
        do { _ = try await waiter.value; XCTFail("Accepted after cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(receiver.isClosed)
    }
    func testTimeoutClosesListener() async throws {
        let receiver = LoopbackCallback(timeout: .milliseconds(50))
        _ = try await receiver.start()
        do { _ = try await receiver.wait(); XCTFail("Did not expire") }
        catch { XCTAssertEqual(error as? LoginFailure, .timedOut) }
        XCTAssertTrue(receiver.isClosed)
    }
    func testBrowserCancellationCannotOverrideAcceptedCallback() {
        var state = LoginHandoff()
        XCTAssertTrue(state.acceptCallback())
        XCTAssertFalse(state.shouldCancelForBrowserDismissal(callbackAccepted: false))
        XCTAssertFalse(state.acceptCallback())
        state.finish()
        XCTAssertFalse(state.acceptCallback())
    }
    func testBrowserCancellationBeforeCallbackRejectsLateCallback() {
        var state = LoginHandoff()
        XCTAssertTrue(state.shouldCancelForBrowserDismissal(callbackAccepted: false))
        state.finish()
        XCTAssertFalse(state.acceptCallback())
    }
}
