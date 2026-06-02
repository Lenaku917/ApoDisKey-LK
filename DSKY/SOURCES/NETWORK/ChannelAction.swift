//
//  ChannelAction.swift
//  ApoDisKey
//
//  Created by Gavin Eadie on Jul16/24 (copyright 2024-25)
//

import Foundation
import AVFoundation

private final class RelaySoundPool {
    private var players: [AVAudioPlayer] = []
    private var rotateIndex = 0
    private let lock = NSLock()

    init(resource: String, ext: String = "aiff", copies: Int = 12) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            logger.error("Missing relay sound resource: \(resource).\(ext)")
            return
        }

        for _ in 0..<copies {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players.append(player)
            } catch {
                logger.error("Unable to load relay sound \(resource): \(error.localizedDescription)")
                break
            }
        }
    }

    func play(volume: Float = 1.0) {
        lock.lock()
        defer { lock.unlock() }

        guard !players.isEmpty else { return }

        if let idle = players.first(where: { !$0.isPlaying }) {
            idle.volume = volume
            idle.currentTime = 0
            idle.play()
            return
        }

        let player = players[rotateIndex]
        player.volume = volume
        player.currentTime = 0
        player.play()
        rotateIndex = (rotateIndex + 1) % players.count
    }
}

private final class RelaySoundboard {
    private let click = RelaySoundPool(resource: "relay_click")
    private let off = RelaySoundPool(resource: "relay_off")

    private let lock = NSLock()
    private var pending = RelayTransitionTally()
    private var flushWorkItem: DispatchWorkItem?
    private let coalesceInterval: TimeInterval = 0.006

    func enqueue(_ tally: RelayTransitionTally) {
        guard tally.total > 0 else { return }

        lock.lock()
        pending.clickCount += tally.clickCount
        pending.offCount += tally.offCount

        let shouldSchedule = (flushWorkItem == nil)
        if shouldSchedule {
            let work = DispatchWorkItem { [weak self] in
                self?.flush()
            }
            flushWorkItem = work
            lock.unlock()
            DispatchQueue.main.asyncAfter(deadline: .now() + coalesceInterval, execute: work)
            return
        }
        lock.unlock()
    }

    private func flush() {
        lock.lock()
        let tally = pending
        pending = RelayTransitionTally()
        flushWorkItem = nil
        lock.unlock()

        guard tally.total > 0 else { return }

        // One sound per visual burst for tight sync with the display update.
        if tally.clickCount >= tally.offCount {
            click.play(volume: 1.0)
        } else {
            off.play(volume: 1.0)
        }
    }
}

nonisolated(unsafe) private let relaySoundboard = RelaySoundboard()

private struct RelayTransitionTally {
    var clickCount = 0
    var offCount = 0

    var total: Int { clickCount + offCount }

    mutating func addClick() { clickCount += 1 }
    mutating func addOff() { offCount += 1 }
}

// Centralized mapping for DSKY status lamp indices
private enum StatusLamp: CustomStringConvertible {
    case uplinkActivity    // index 11
    case noAttitude        // index 12
    case standby           // index 13
    case operatorError     // index 14
    case operError         // alias if needed (kept separate for clarity)
    case keyRelease        // index 24 (011 semantics) / restart (163 semantics), see mapping
    case tempWarning       // index 21
    case velocity          // index 27
    case altitude          // index 26
    case gimbalLock        // index 22
    case tracker           // index 25
    case program           // index 23
    case restart           // index 24

    var description: String {
        switch self {
            case .uplinkActivity: return "Uplink Activity"
            case .noAttitude:     return "No Attitude"
            case .standby:        return "Standby"
            case .operatorError:  return "Operator Error"
            case .operError:      return "Oper Error"
            case .keyRelease:     return "Key Release"
            case .tempWarning:    return "Temp Warning"
            case .altitude:       return "Altitude"
            case .velocity:       return "Velocity"
            case .gimbalLock:     return "Gimbal Lock"
            case .tracker:        return "Tracker"
            case .program:        return "Program"
            case .restart:        return "Restart"
        }
    }
}

private extension Dictionary where Key == Int, Value == (String, BackColor) {
    subscript(_ lamp: StatusLamp) -> (String, BackColor)? {
        get {
            self[StatusLamp.index(for: lamp)]
        }
        set {
            if let newValue = newValue {
                self[StatusLamp.index(for: lamp)] = newValue
            }
        }
    }
}

private extension StatusLamp {
    static func index(for lamp: StatusLamp) -> Int {
        switch lamp {
        case .uplinkActivity: return 11
        case .noAttitude:     return 12
        case .standby:        return 13
        case .operatorError:  return 14
        case .operError:      return 15 // used in channel 163 mapping in existing code
        case .tempWarning:    return 21
        case .altitude:       return 26
        case .velocity:       return 27
        case .gimbalLock:     return 22
        case .tracker:        return 25
        case .program:        return 23
        case .keyRelease:     return 24
        case .restart:        return 24
        }
    }
}

func channelAction(_ channel: UInt16, _ value: UInt16, _ boolean: Bool = true) {

    switch channel {
        case 0o005...0o006:
            break

        case 0o010:                 // [OUTPUT] drives DSKY electroluminescent panel
            dskyInterpretation(value)

        case 0o011:                 // [OUTPUT] flags for indicator lamps etc
            if (value & 0b1101111111111101) != 0x0000 {        // if not COMP_ACTY
                logDSKY("011", bitsLabel: "15",
                        value: value, pretty: prettyCh011(value))
            }

            model.comp.1 = value & DSKY.Ch011.compActivity > 0

            setLamp(.uplinkActivity, to: (value & DSKY.Ch011.uplinkActivity > 0) ? .white  : .off, reason: "CH011")
            setLamp(.tempWarning,    to: (value & DSKY.Ch011.tempWarning    > 0) ? .yellow : .off, reason: "CH011")
            setLamp(.keyRelease,     to: (value & DSKY.Ch011.keyRelease     > 0) ? .yellow : .off, reason: "CH011")
            setLamp(.operatorError,  to: (value & DSKY.Ch011.operatorError  > 0) ? .white  : .off, reason: "CH011")

        case 0o013:                 // [OUTPUT] DSKY lamp tests ..
            setLamp(.standby, to: (value & DSKY.Ch013.standby > 0) ? .white : .off, reason: "CH013")

        case 0o015:                 // [INPUT] Used for inputting keystrokes from the DSKY. ..
            let keyString = keyText(value).replacingOccurrences(of: "\n", with: " ")
            logDSKY("015", bitsLabel: "8",
                    value: value, note: "\(value) = \"\(keyString)\"")

            if keyDict[value] == "RSET" {
                model.ch15ResetCount += 1
                if model.ch15ResetCount == 5 { exit(EXIT_SUCCESS) }             // 5 and we quit
            }

        case 0o012,                 // [OUTPUT] CM and LM actions ..
             0o014,                 // CM and LM Gyro selection ..
             0o016...0o031,
             0o032,                 // [INPUT] Bit 14 UNSET indicates that the PRO key is pressed.
             0o033...0o035:         // [OUTPUT] CM and LM downlinks (ch 34, 35)
            break

        case 0o077:                 // [OUTPUT] source of a hardware restart ..
            logDSKY("077", value: value, note: "H/W RESET")

        case 0o163:
            logDSKY("163", bitsLabel: "10",
                    value: value, pretty: prettyCh163(value))

            setLamp(.tempWarning, to: (value & DSKY.Ch163.tempLamp    > 0) ? .yellow : .off, reason: "CH163")
            setLamp(.keyRelease,  to: (value & DSKY.Ch163.keyRelLamp  > 0) ? .white  : .off, reason: "CH163")
            setLamp(.operError,   to: (value & DSKY.Ch163.operErrLamp > 0) ? .white  : .off, reason: "CH163")
            setLamp(.restart,     to: (value & DSKY.Ch163.restartLamp > 0) ? .yellow : .off, reason: "CH163")
            setLamp(.standby,     to: (value & DSKY.Ch163.standbyLamp > 0) ? .white  : .off, reason: "CH163")

            model.verb.1 = value & DSKY.Ch163.verbNounFlash == 0
            model.noun.1 = value & DSKY.Ch163.verbNounFlash == 0

            let newELPowerOn = value & DSKY.Ch163.elPowerOff == 0
            if model.elPowerOn != newELPowerOn {
                logger.log("EL Power: \(newELPowerOn ? "ON" : "OFF") via CH163")
            }
            model.elPowerOn = newELPowerOn

        case 0o165:
            logDSKY("165", value: value, note: "TIME1")

        case 0o164, 0o166...0o177:
            logDSKY(String(format: "%03o", channel), value: value, note: "fiction")

        default:
            logDSKY(String(format: "%03o", channel), value: value, note: "unknown")

    }
}

func dskyInterpretation(_ code: UInt16) {

    let rowCode = DSKY.extractRowCode(from: code)

    if rowCode == 0 { return }      // logger.log("ooo    DSKY 010: \(ZeroPadWord(code))")

    if rowCode == 12 {
        logDSKY("010", bitsLabel: "10",
                value: code & 0b00000001_11111111,
                pretty: prettyCh010(code & 0b00000001_11111111))

        setLamp(.velocity,    to: (code & DSKY.Ch010_Lights.velocity   > 0) ? .yellow : .off, reason: "CH010")
        setLamp(.noAttitude,  to: (code & DSKY.Ch010_Lights.noAttitude > 0) ? .white  : .off, reason: "CH010")
        setLamp(.altitude,    to: (code & DSKY.Ch010_Lights.altitude   > 0) ? .yellow : .off, reason: "CH010")
        setLamp(.gimbalLock,  to: (code & DSKY.Ch010_Lights.gimbalLock > 0) ? .yellow : .off, reason: "CH010")
        setLamp(.tracker,     to: (code & DSKY.Ch010_Lights.tracker    > 0) ? .yellow : .off, reason: "CH010")
        setLamp(.program,     to: (code & DSKY.Ch010_Lights.program    > 0) ? .yellow : .off, reason: "CH010")
    } else {
        var relayTally = RelayTransitionTally()

        let bBit: Bool =   (code & 0b00000_1_00000_00000) >  0
        let cInt: UInt16 = (code & 0b00000_0_11111_00000) >> 5
        let dInt: UInt16 = (code & 0b00000_0_00000_11111) >> 0

        let aStr = rowCode < symbolArray.count ? symbolArray[Int(rowCode)] : "????"
        let cStr = digitsDict[Int(cInt)] ?? "?"
        let dStr = digitsDict[Int(dInt)] ?? "?"

        let seg = "(\(aStr)) ±\(bBit ? "↑" : "↓") \"\(cStr)\(dStr)\""
        logDSKY("010", value: code, note: seg)

        switch rowCode {
            case 9:
                playDigitTransitions(from: Array(model.noun.0), to: [cStr, dStr], tally: &relayTally)
                model.noun = (cStr + dStr, true)

            case 10:
                playDigitTransitions(from: Array(model.verb.0), to: [cStr, dStr], tally: &relayTally)
                model.verb = (cStr + dStr, true)

            case 11:
                playDigitTransitions(from: Array(model.mode.0), to: [cStr, dStr], tally: &relayTally)
                model.mode = (cStr + dStr, true)

            default: break
        }

        var reg1Bytes: [String] = model.reg1.0.map { String($0) }
        var reg2Bytes: [String] = model.reg2.0.map { String($0) }
        var reg3Bytes: [String] = model.reg3.0.map { String($0) }

        guard reg1Bytes.count == 6, [" ", "+", "-"].contains(reg1Bytes[0]) else {
            logger.error("ERROR: Invalid register format for reg1: \(model.reg1.0)")
            return
        }
        guard reg2Bytes.count == 6, [" ", "+", "-"].contains(reg2Bytes[0]) else {
            logger.error("ERROR: Invalid register format for reg2: \(model.reg2.0)")
            return
        }
        guard reg3Bytes.count == 6, [" ", "+", "-"].contains(reg3Bytes[0]) else {
            logger.error("ERROR: Invalid register format for reg3: \(model.reg3.0)")
            return
        }

        switch rowCode {
            case 8:         // "..11"
                playDigitTransition(from: reg1Bytes[1], to: dStr, tally: &relayTally)
                reg1Bytes[1] = dStr
                model.reg1.0 = reg1Bytes.joined()

            case 3:         // "2531"
                playDigitTransition(from: reg2Bytes[5], to: cStr, tally: &relayTally)
                reg2Bytes[5] = cStr
                model.reg2.0 = reg2Bytes.joined()

                playDigitTransition(from: reg3Bytes[1], to: dStr, tally: &relayTally)
                reg3Bytes[1] = dStr
                model.reg3.0 = reg3Bytes.joined()

            case 7:         // "1213" & "R1+"
                model.r1Sign.0 = bBit
                reg1Bytes[0] = plu_min(model.r1Sign)

                playDigitTransition(from: reg1Bytes[2], to: cStr, tally: &relayTally)
                reg1Bytes[2] = cStr

                playDigitTransition(from: reg1Bytes[3], to: dStr, tally: &relayTally)
                reg1Bytes[3] = dStr
                model.reg1.0 = reg1Bytes.joined()

            case 6:         // "1415" & "R1-"
                model.r1Sign.1 = bBit
                reg1Bytes[0] = plu_min(model.r1Sign)

                playDigitTransition(from: reg1Bytes[4], to: cStr, tally: &relayTally)
                reg1Bytes[4] = cStr

                playDigitTransition(from: reg1Bytes[5], to: dStr, tally: &relayTally)
                reg1Bytes[5] = dStr
                model.reg1.0 = reg1Bytes.joined()

            case 5:         // "2122" & "R2+"
                model.r2Sign.0 = bBit
                reg2Bytes[0] = plu_min(model.r2Sign)

                playDigitTransition(from: reg2Bytes[1], to: cStr, tally: &relayTally)
                reg2Bytes[1] = cStr

                playDigitTransition(from: reg2Bytes[2], to: dStr, tally: &relayTally)
                reg2Bytes[2] = dStr
                model.reg2.0 = reg2Bytes.joined()

            case 4:         // "2324" & "R2-"
                model.r2Sign.1 = bBit
                reg2Bytes[0] = plu_min(model.r2Sign)

                playDigitTransition(from: reg2Bytes[3], to: cStr, tally: &relayTally)
                reg2Bytes[3] = cStr

                playDigitTransition(from: reg2Bytes[4], to: dStr, tally: &relayTally)
                reg2Bytes[4] = dStr
                model.reg2.0 = reg2Bytes.joined()

            case 2:         // "3233" & "R3+"
                model.r3Sign.0 = bBit
                reg3Bytes[0] = plu_min(model.r3Sign)

                playDigitTransition(from: reg3Bytes[2], to: cStr, tally: &relayTally)
                reg3Bytes[2] = cStr

                playDigitTransition(from: reg3Bytes[3], to: dStr, tally: &relayTally)
                reg3Bytes[3] = dStr
                model.reg3.0 = reg3Bytes.joined()

            case 1:         // "3435" & "R3-"
                model.r3Sign.1 = bBit
                reg3Bytes[0] = plu_min(model.r3Sign)

                playDigitTransition(from: reg3Bytes[4], to: cStr, tally: &relayTally)
                reg3Bytes[4] = cStr

                playDigitTransition(from: reg3Bytes[5], to: dStr, tally: &relayTally)
                reg3Bytes[5] = dStr
                model.reg3.0 = reg3Bytes.joined()

            default: break
        }

        enqueueRelaySound(for: relayTally)
    }

    return
}

private func playDigitTransitions(from oldChars: [Character],
                                  to newDigits: [String],
                                  tally: inout RelayTransitionTally) {
    for (index, newDigit) in newDigits.enumerated() where index < oldChars.count {
        playDigitTransition(from: String(oldChars[index]), to: newDigit, tally: &tally)
    }
}

private func playDigitTransition(from oldDigit: String,
                                 to newDigit: String,
                                 tally: inout RelayTransitionTally) {
    guard oldDigit != newDigit else { return }

    if newDigit == "_" {
        tally.addOff()
    } else if isDskyNumericDigit(newDigit) {
        tally.addClick()
    }
}

private func enqueueRelaySound(for tally: RelayTransitionTally) {
    relaySoundboard.enqueue(tally)
}

private func isDskyNumericDigit(_ value: String) -> Bool {
    guard value.count == 1, let scalar = value.unicodeScalars.first else { return false }
    return CharacterSet.decimalDigits.contains(scalar)
}

private func logDSKY(_ channel: String,
                     bitsLabel: String? = nil,
                     value: UInt16,
                     pretty: String? = nil,
                     note: String? = nil) {
    let word = (bitsLabel == "10") ? zeroPadWord(value, to: 10) :
               (bitsLabel == "8") ? zeroPadWord(value, to: 8) :
                                    zeroPadWord(value)
    var line = "»»» DSKY \(channel): \(word)"
    if let bitsLabel = bitsLabel { line += " BITS (\(bitsLabel))" }
    if let pretty { line += " :: \(pretty)" }
    if let note { line += " :: \(note)" }
    logger.log("\(line)")
}

private func setLamp(_ lamp: StatusLamp,
                     to color: BackColor,
                     reason: String) {
    let index = StatusLamp.index(for: lamp)
    if let current = model.lights[index]?.1, current != color {
        logger.log("""
            Lamp: \(lamp) [\(String(describing: current))→\(String(describing: color))] \
            via \(reason)
            """
        )
    }
    model.lights[lamp]?.1 = color
}
