//
//  Network.swift
//  ApoDisKey
//
//  Local replacement for the unavailable ApolloNetwork package.
//

import Foundation
import Darwin

enum ConnectionState {
    case none
    case setup
    case preparing
    case ready
    case waiting
    case failed
    case cancelled
}

@Observable
final class ConnectionStatus {
    var state: ConnectionState = .none
}

enum NetworkFailure: Error {
    case invalidEndpoint
    case resolveFailed(Int32)
    case connectFailed(Int32)
    case sendFailed(Int32)
    case receiveFailed(Int32)
    case disconnected
}

final class Network: @unchecked Sendable {
    var connection = ConnectionStatus()

    private let host: String
    private let port: UInt16
    private var socketFD: Int32 = -1
    private let connectLock = NSLock()

    init() {
        self.host = "localhost"
        self.port = 19697
        connection.state = .none
    }

    convenience init(_ host: String, _ port: UInt16) {
        self.init(host, port, connect: false)
    }

    init(_ host: String, _ port: UInt16, connect: Bool = false) {
        self.host = host
        self.port = port
        connection.state = .setup

        if connect {
            start()
        }
    }

    deinit {
        closeSocket()
    }

    func start() {
        do {
            try openSocketIfNeeded()
        } catch {
            connection.state = .failed
        }
    }

    func receive(length: Int) async throws -> Data {
        guard length > 0 else { return Data() }

        try openSocketIfNeeded()
        var data = Data(count: length)
        var offset = 0

        while offset < length {
            let readCount: Int = data.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress else { return -1 }
                return Darwin.recv(socketFD, base.advanced(by: offset), length - offset, 0)
            }

            if readCount > 0 {
                offset += readCount
            } else if readCount == 0 {
                handleFailureState()
                throw NetworkFailure.disconnected
            } else {
                if errno == EINTR { continue }
                handleFailureState()
                throw NetworkFailure.receiveFailed(errno)
            }
        }

        return data
    }

    func send(_ data: Data) async throws {
        if data.isEmpty { return }

        try openSocketIfNeeded()
        var sent = 0

        while sent < data.count {
            let writeCount: Int = data.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return -1 }
                return Darwin.send(socketFD, base.advanced(by: sent), data.count - sent, 0)
            }

            if writeCount > 0 {
                sent += writeCount
            } else {
                if errno == EINTR { continue }
                handleFailureState()
                throw NetworkFailure.sendFailed(errno)
            }
        }
    }

    private func openSocketIfNeeded() throws {
        connectLock.lock()
        defer { connectLock.unlock() }

        if socketFD >= 0 {
            connection.state = .ready
            return
        }

        guard !host.isEmpty, port > 0 else {
            connection.state = .none
            throw NetworkFailure.invalidEndpoint
        }

        connection.state = .preparing

        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var infoPtr: UnsafeMutablePointer<addrinfo>?
        let portString = String(port)
        let resolveResult = getaddrinfo(host, portString, &hints, &infoPtr)
        guard resolveResult == 0 else {
            connection.state = .failed
            throw NetworkFailure.resolveFailed(resolveResult)
        }
        defer { freeaddrinfo(infoPtr) }

        var candidate = infoPtr
        while let info = candidate?.pointee {
            let fd = Darwin.socket(info.ai_family, info.ai_socktype, info.ai_protocol)
            if fd >= 0 {
                var opt: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))

                let connectResult = Darwin.connect(fd, info.ai_addr, info.ai_addrlen)
                if connectResult == 0 {
                    socketFD = fd
                    connection.state = .ready
                    return
                }

                Darwin.close(fd)
            }

            candidate = info.ai_next
        }

        connection.state = .failed
        throw NetworkFailure.connectFailed(errno)
    }

    private func handleFailureState() {
        connection.state = .failed
        closeSocket()
    }

    private func closeSocket() {
        connectLock.lock()
        defer { connectLock.unlock() }

        if socketFD >= 0 {
            Darwin.shutdown(socketFD, SHUT_RDWR)
            Darwin.close(socketFD)
            socketFD = -1
        }
    }
}
