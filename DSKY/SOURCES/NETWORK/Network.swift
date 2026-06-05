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
    private let port: Int
    private var socketFD: Int32 = -1
    private let connectLock = NSLock()
    private var receiveTask: Task<Void, Never>?

    private func setConnectionState(_ state: ConnectionState) {
        if Thread.isMainThread {
            connection.state = state
        } else {
            DispatchQueue.main.async { [connection] in
                connection.state = state
            }
        }
    }

    init() {
        self.host = "localhost"
        self.port = 19697
        setConnectionState(.none)
    }

    convenience init(_ host: String, _ port: Int) {
        self.init(host, port, connect: false)
    }

    init(_ host: String, _ port: Int, connect: Bool = false) {
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port
        setConnectionState(.setup)

        if connect {
            start()
        }
    }

    deinit {
        receiveTask?.cancel()
        closeSocket()
    }

    func startDSKYReceiveLoop() {
        guard connection.state == .ready else { return }

        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    let (channel, action, _) = try parseIoPacket(try await self.receive(length: 4))
                    channelAction(channel, action)
                } catch PacketError.ignore_FF_FF_FF_FF {
                } catch {
                    if Task.isCancelled { break }
                    logger.error("←→ rx loop exit: \(error.localizedDescription)")
                    model.elPowerOn = false
                    break
                }
            }
        }
    }

    func sendDSKY032ReadyFromMonitor() {
        Task { [weak self] in
            guard let self else { return }

            let value: UInt16 = 0b0010_0000_0000_0000
            do {
                try await self.send(formIoPacket(0o0232, value))
                logger.log("«««    DSKY 032:    \(zeroPadWord(value)) BITS (15)")
            } catch {
                logger.error("\(error.localizedDescription)")
                model.elPowerOn = false
            }
        }
    }

    func start() {
        do {
            try openSocketIfNeeded()
        } catch {
            setConnectionState(.failed)
        }
    }

    func stop() {
        setConnectionState(.cancelled)
        receiveTask?.cancel()
        closeSocket()
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
            setConnectionState(.ready)
            return
        }

        guard !host.isEmpty, port > 0 else {
            setConnectionState(.none)
            throw NetworkFailure.invalidEndpoint
        }

        setConnectionState(.preparing)

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
            setConnectionState(.failed)
            throw NetworkFailure.resolveFailed(resolveResult)
        }
        defer { freeaddrinfo(infoPtr) }

        var candidate = infoPtr
        var lastConnectError: Int32 = 0
        while let info = candidate?.pointee {
            let fd = Darwin.socket(info.ai_family, info.ai_socktype, info.ai_protocol)
            if fd >= 0 {
                configureSocket(fd)

                let connectResult = Darwin.connect(fd, info.ai_addr, info.ai_addrlen)
                if connectResult == 0 {
                    socketFD = fd
                    setConnectionState(.ready)
                    return
                }

                lastConnectError = errno
                Darwin.close(fd)
            }

            candidate = info.ai_next
        }

        setConnectionState(.failed)
        throw NetworkFailure.connectFailed(lastConnectError)
    }

    private func handleFailureState() {
        setConnectionState(.failed)
        closeSocket()
    }

    private func configureSocket(_ fd: Int32) {
        var enabled: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        _ = setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &enabled, socklen_t(MemoryLayout<Int32>.size))
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
