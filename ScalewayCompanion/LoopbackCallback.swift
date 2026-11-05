// SPDX-License-Identifier: MPL-2.0
import Foundation
import Network

// Browser cancellation is expected after a local handoff; only the first event wins.
struct LoginHandoff {
    private var accepted = false
    private var finished = false
    func shouldCancelForBrowserDismissal(callbackAccepted: Bool) -> Bool { !accepted && !finished && !callbackAccepted }
    mutating func acceptCallback() -> Bool {
        guard !accepted && !finished else { return false }
        accepted = true
        return true
    }
    mutating func finish() { finished = true }
}

extension LoginAttempt {
    func decodeRequest(_ data: Data) throws -> SessionEnvelope? {
        guard data.count <= 65_536 else { throw LoginFailure.invalidCallback }
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard end.upperBound == data.endIndex,
              let header = String(data: data[..<end.lowerBound], encoding: .utf8) else { throw LoginFailure.invalidCallback }
        let lines = header.components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard start.count == 3, start[0] == "GET", start[2] == "HTTP/1.1",
              start[1].hasPrefix("/"), !start[1].hasPrefix("//") else { throw LoginFailure.invalidCallback }
        var hosts = [String]()
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { throw LoginFailure.invalidCallback }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "host" { hosts.append(value) }
            if name == "transfer-encoding" || (name == "content-length" && value != "0") { throw LoginFailure.invalidCallback }
        }
        guard hosts == ["localhost:\(port)"],
              let url = URL(string: "http://localhost:\(port)\(start[1])") else { throw LoginFailure.invalidCallback }
        return try decodeCallback(url)
    }
}

@MainActor
final class LoopbackCallback {
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var ready: CheckedContinuation<LoginAttempt, Error>?
    private var waiter: CheckedContinuation<SessionEnvelope, Error>?
    private var result: Result<SessionEnvelope, Error>?
    private var attempt: LoginAttempt?
    private var timer: Task<Void, Never>?
    private let timeout: Duration
    private(set) var isClosed = false
    private(set) var callbackAccepted = false

    init(timeout: Duration = .seconds(180)) { self.timeout = timeout }

    func start() async throws -> LoginAttempt {
        guard listener == nil, !isClosed else { throw LoginFailure.listenerUnavailable }
        let parameters = NWParameters.tcp
        // Interface restriction applies to both IPv4 and IPv6, excluding Wi-Fi/cellular.
        parameters.requiredInterfaceType = .loopback
        parameters.includePeerToPeer = false
        let server = try NWListener(using: parameters, on: .any)
        listener = server
        server.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        server.stateUpdateHandler = { [weak self, weak server] state in
            Task { @MainActor in
                guard let self, !self.isClosed else { return }
                switch state {
                case .ready:
                    guard let port = server?.port?.rawValue else { self.finish(.failure(LoginFailure.listenerUnavailable)); return }
                    let attempt = LoginAttempt(port: port)
                    self.attempt = attempt
                    self.ready?.resume(returning: attempt)
                    self.ready = nil
                case .failed: self.finish(.failure(LoginFailure.listenerUnavailable))
                default: break
                }
            }
        }
        timer = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.finish(.failure(LoginFailure.timedOut))
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                ready = continuation
                server.start(queue: .main)
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }

    func wait() async throws -> SessionEnvelope {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if let result { self.result = nil; return try result.get() }
            guard !isClosed, waiter == nil else { throw CancellationError() }
            return try await withCheckedThrowingContinuation { waiter = $0 }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }

    func cancel() { finish(.failure(CancellationError())); result = nil }

    private func accept(_ connection: NWConnection) {
        guard !isClosed, connections.count < 4 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: .main)
        // Bound slow/incomplete requests as well as total attempt duration.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak connection] in
            guard self?.connections.removeValue(forKey: id) != nil else { return }
            connection?.cancel()
        }
        receive(connection, id: id, buffer: Data())
    }

    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_537 - buffer.count) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, !self.isClosed, self.connections[id] != nil else { connection.cancel(); return }
                var buffer = buffer
                if let data { buffer.append(data) }
                do {
                    guard let attempt = self.attempt else { throw LoginFailure.invalidCallback }
                    if let envelope = try attempt.decodeRequest(buffer) {
                        self.callbackAccepted = true
                        self.connections.removeValue(forKey: id)
                        self.respond(connection, accepted: true)
                        self.finish(.success(envelope))
                    } else if complete || error != nil { throw LoginFailure.invalidCallback }
                    else { self.receive(connection, id: id, buffer: buffer) }
                } catch {
                    self.connections.removeValue(forKey: id)
                    self.respond(connection, accepted: false)
                }
            }
        }
    }

    private func respond(_ connection: NWConnection, accepted: Bool) {
        let body = accepted ? "Sign-in received. Return to the app." : "Callback not accepted."
        let response = "HTTP/1.1 \(accepted ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { connection.cancel() }
    }

    private func finish(_ outcome: Result<SessionEnvelope, Error>) {
        guard !isClosed else { return }
        isClosed = true
        listener?.cancel(); listener = nil
        connections.values.forEach { $0.cancel() }; connections.removeAll()
        timer?.cancel(); timer = nil
        attempt = nil
        if let ready { self.ready = nil; ready.resume(throwing: outcome.failure ?? LoginFailure.listenerUnavailable) }
        if let waiter { self.waiter = nil; waiter.resume(with: outcome) }
        else { result = outcome }
    }
}

private extension Result {
    var failure: Failure? { if case .failure(let error) = self { return error }; return nil }
}
