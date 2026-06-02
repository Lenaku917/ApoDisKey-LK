//
//  PacketCodec.swift
//  ApoDisKey
//
//  Local packet codec replacement for the removed ApolloNetwork dependency.
//

import Foundation

enum PacketError: Error {
    case invalidLength(Int)
    case invalidChannel(UInt16)
    case invalidValue(UInt16)
    case invalidSignature([UInt8])
    case ignore_FF_FF_FF_FF
}

func formIoPacket(_ channel: UInt16, _ action: UInt16) -> Data {
    // yaAGC packet format: 00pppppp 01pppddd 10dddddd 11dddddd
    // p = 9-bit channel (includes u-bit), d = 15-bit value.
    guard channel <= 0x01FF else { return Data() }
    guard action <= 0x7FFF else { return Data() }

    var bytes = [UInt8](repeating: 0, count: 4)
    bytes[0] = UInt8((channel >> 3) & 0x003F)
    bytes[1] = 0x40 | UInt8(((channel << 3) & 0x0038) | ((action >> 12) & 0x0007))
    bytes[2] = 0x80 | UInt8((action >> 6) & 0x003F)
    bytes[3] = 0xC0 | UInt8(action & 0x003F)
    return Data(bytes)
}

func parseIoPacket(_ data: Data) throws -> (UInt16, UInt16, UInt16) {
    guard data.count == 4 else {
        throw PacketError.invalidLength(data.count)
    }

    if data == Data([0xFF, 0xFF, 0xFF, 0xFF]) {
        throw PacketError.ignore_FF_FF_FF_FF
    }

    let b0 = data[0]
    let b1 = data[1]
    let b2 = data[2]
    let b3 = data[3]

    guard (b0 & 0xC0) == 0x00,
          (b1 & 0xC0) == 0x40,
          (b2 & 0xC0) == 0x80,
          (b3 & 0xC0) == 0xC0 else {
        throw PacketError.invalidSignature([b0, b1, b2, b3])
    }

    // Channel returned here is the 8-bit channel number expected by channelAction().
    let channel = ((UInt16(b0 & 0x1F) << 3) | ((UInt16(b1) >> 3) & 0x0007)) & 0x00FF
    let action = ((UInt16(b1) << 12) & 0x7000) |
                 ((UInt16(b2) << 6)  & 0x0FC0) |
                 (UInt16(b3)         & 0x003F)
    let uBit = UInt16(b0 & 0x20)

    return (channel, action, uBit)
}
