//
//  ChannelAction.swift
//  ApoDisKey
//
//  Created by Gavin Eadie on Jul16/24 (copyright 2024-25)
//
//  OVERVIEW:
//  This module handles AGC (Apollo Guidance Computer) channel commands that drive the DSKY display.
//  It simulates the electromechanical relay behavior of the real DSKY by:
//  - Coalescing rapid display changes into bursts of relay click/off sounds
//  - Using weighted energy curves to simulate realistic loudness layering
//  - Applying per-lamp weights to match acoustic properties (left column lamps are quieter)
//  - Processing channels 010 (digit displays), 011 & 163 (lamps), and 013 (lamp test)
//
//  THREAD SAFETY:
//  - All lamp and digit updates are dispatched to the main thread
//  - RelaySoundboard uses NSLock for thread-safe audio enqueue/flush
//  - Model state updates occur only on main thread
//
//  APOLLO DSKY PHYSICS SIMULATED:
//  - Relays physically move when powered, creating "click" and "off" sounds
//  - Multiple relays activating within ~6ms are heard as a composite burst
//  - Loudness increases logarithmically with event count (saturation curve)
//  - Left-column status lamps are acoustically softer than right-column lamps
//  - Lamp colors match real DSKY: white (uplink, standby, no-attitude, OPR ERR, KEY REL)
//    and yellow (TEMP, RESTART, and all CH010 lights)
//

import Foundation
import AVFoundation

// MARK: - Relay Audio Configuration Constants

private let RELAY_SOUND_POOL_SIZE = 12  // Number of concurrent audio players per sound type
private let RELAY_SATURATION_EXPONENT: Float = 0.62  // Exponential curve factor: higher = faster saturation
private let RELAY_CLICK_BASE_VOLUME: Float = 0.10  // Baseline volume when no other clicks
private let RELAY_CLICK_HEADROOM: Float = 0.72  // Volume gain headroom for click-dominant bursts
private let RELAY_OFF_BASE_VOLUME: Float = 0.08  // Baseline volume for off transitions
private let RELAY_OFF_HEADROOM: Float = 0.65  // Volume gain headroom for off-dominant bursts
private let LAMP_WEIGHT_LEFT_COLUMN: Float = 0.12  // Energy weight for left annunciators (11-17)
private let LAMP_WEIGHT_RIGHT_COLUMN: Float = 0.50  // Energy weight for right annunciators
private let COALESCE_INTERVAL_MIN: TimeInterval = 0.001  // Minimum relay coalesce time (1ms)

/// Manages a pool of AVAudioPlayer instances for a single sound type (e.g., relay_click).
/// Uses round-robin scheduling to play multiple overlapping sounds without clipping.
/// Thread-safe with NSLock protecting the player array and rotate index.
private final class RelaySoundPool {
    private var players: [AVAudioPlayer] = []
    private var rotateIndex = 0
    private let lock = NSLock()

    init(resource: String, ext: String = "aiff", copies: Int = RELAY_SOUND_POOL_SIZE) {
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

    /// Play a sound from the pool at the specified volume.
    /// If an idle player is available, uses that; otherwise round-robins through the pool.
    /// This allows multiple relay clicks to overlap naturally without interference.
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

/// Coalesces relay transitions into burst events and plays them with realistic layering.
///
/// APOLLO DSKY RELAY SIMULATION:
/// The real DSKY has electromagnetic relays that activate/deactivate based on AGC channel bits.
/// When relays move, they produce audible "click" (engaging) and "off" (disengaging) sounds.
/// If multiple relays activate within ~6ms, their sounds merge into a single burst.
///
/// This class:
/// 1. Accepts transition tallies from display updates
/// 2. Accumulates energy (weighted click/off counts) within a coalesce window
/// 3. Plays both sounds if mixed (some on, some off) with independent volumes
/// 4. Uses saturation curve to prevent unnaturally loud bursts
///
private final class RelaySoundboard {
    private let click = RelaySoundPool(resource: "relay_click")
    private let off = RelaySoundPool(resource: "relay_off")

    private let lock = NSLock()
    private var pending = RelayTransitionTally()
    private var flushWorkItem: DispatchWorkItem?

    private var coalesceInterval: TimeInterval {
        max(COALESCE_INTERVAL_MIN, model.audioSyncTimeS)
    }

    /// Compute output volume using saturation curve to simulate realistic relay burst loudness.
    ///
    /// Formula: volume = base + headroom * (1 - exp(-exponent * energy))
    ///
    /// Behavior:
    /// - Single event: volume ≈ base (quiet)
    /// - Few events: volume grows logarithmically
    /// - Many events: volume asymptotically approaches (base + headroom), never exceeding 1.0
    ///
    /// This matches real DSKY behavior: multiple relays don't make a linearly louder burst,
    /// but rather a denser, richer sound that eventually saturates.
    private func layeredVolume(for energy: Float, isClickDominant: Bool) -> Float {
        let clampedEnergy = max(0, energy)
        let curve = 1 - expf(-RELAY_SATURATION_EXPONENT * clampedEnergy)
        let base: Float = isClickDominant ? RELAY_CLICK_BASE_VOLUME : RELAY_OFF_BASE_VOLUME
        let headroom: Float = isClickDominant ? RELAY_CLICK_HEADROOM : RELAY_OFF_HEADROOM
        return min(1.0, base + headroom * curve)
    }

    /// Enqueue a relay transition tally to be played after the coalesce window.
    /// If no flush is already scheduled, schedules one on the main thread.
    /// Thread-safe: uses NSLock to protect pending state.
    func enqueue(_ tally: RelayTransitionTally) {
        guard tally.total > 0 else { return }

        if model.audioMutedAll || model.audioRelayClicksMuted {
            lock.lock()
            pending = RelayTransitionTally()
            flushWorkItem?.cancel()
            flushWorkItem = nil
            lock.unlock()
            return
        }

        lock.lock()
        pending.clickCount += tally.clickCount
        pending.offCount += tally.offCount
        pending.clickWeight += tally.clickWeight
        pending.offWeight += tally.offWeight

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

    /// Flush accumulated transitions: extract pending tally, compute volumes, and play sounds.
    /// Respects audio mute flags. Thread-safe with NSLock.
    ///
    /// Plays:
    /// - Both sounds if mixed transitions present (some relays on, some off)
    /// - Single dominant sound if only one transition type
    /// - Nothing if muted or no transitions pending
    private func flush() {
        if model.audioMutedAll || model.audioRelayClicksMuted {
            lock.lock()
            pending = RelayTransitionTally()
            flushWorkItem = nil
            lock.unlock()
            return
        }

        lock.lock()
        let tally = pending
        pending = RelayTransitionTally()
        flushWorkItem = nil
        lock.unlock()

        guard tally.total > 0 else { return }

        // Play both sounds if mixed transitions (some on, some off) are present.
        if tally.clickWeight > 0 && tally.offWeight > 0 {
            let clickVol = layeredVolume(for: tally.clickWeight, isClickDominant: true)
            let offVol = layeredVolume(for: tally.offWeight, isClickDominant: false)
            click.play(volume: clickVol)
            off.play(volume: offVol)
        } else {
            // Only one transition type; play dominant with full layering curve.
            let clickDominant = tally.clickWeight >= tally.offWeight
            let dominantEnergy = clickDominant ? tally.clickWeight : tally.offWeight
            let volume = layeredVolume(for: dominantEnergy, isClickDominant: clickDominant)

            if clickDominant {
                click.play(volume: volume)
            } else {
                off.play(volume: volume)
            }
        }
        //logger.log("Relay interval: \(self.coalesceInterval)")
    }
}

nonisolated(unsafe) private let relaySoundboard = RelaySoundboard()

/// Accumulates relay transition energies for a single flush event.
/// Tracks both count and weighted energy for click and off transitions.
/// Weights allow per-lamp sound contribution (e.g., left lamps are quieter).
private struct RelayTransitionTally {
    var clickCount = 0
    var offCount = 0
    var clickWeight: Float = 0
    var offWeight: Float = 0

    var total: Int { clickCount + offCount }

    mutating func addClick(weight: Float = 1.0) {
        clickCount += 1
        clickWeight += max(0, weight)
    }

    mutating func addOff(weight: Float = 1.0) {
        offCount += 1
        offWeight += max(0, weight)
    }
}

/// Maps logical DSKY annunciator lamp names to their physical indices (11-27).
/// Ensures consistent lamp addressing across all AGC channels (011, 013, 010, 163).
private enum StatusLamp: CustomStringConvertible {
    case uplinkActivity    // index 11
    case noAttitude        // index 12
    case standby           // index 13
    case operatorError     // index 15
    case keyRelease        // index 14
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
        case .operatorError:  return 15  // OPR ERR
        case .tempWarning:    return 21
        case .altitude:       return 26
        case .velocity:       return 27
        case .gimbalLock:     return 22
        case .tracker:        return 25
        case .program:        return 23
        case .keyRelease:     return 14  // KEY REL
        case .restart:        return 24  // RESTART
        }
    }
}

/// Process incoming AGC channel command and update display state.
///
/// Dispatches to main thread if needed to ensure serial execution.
/// Routes to appropriate handler based on channel number:
/// - CH010: Display data (digits, registers, signs)
/// - CH011: Status lamp latches (UPLINK, TEMP, KEY REL, OPR ERR)
/// - CH013: Lamp test control
/// - CH015: Keyboard input
/// - CH163: More status lamps (TEMP, KEY REL, OPR ERR, RESTART, STANDBY) + VERB/NOUN flash + EL power
///
/// All relay transitions are accumulated and played as coalesced bursts.
func channelAction(_ channel: UInt16, _ value: UInt16, _ boolean: Bool = true) {

    if !Thread.isMainThread {
        DispatchQueue.main.async {
            channelAction(channel, value, boolean)
        }
        return
    }

    switch channel {
        case 0o005...0o006:
            break

        case 0o010:                 // [OUTPUT] CH010: DSKY electroluminescent panel display data
            dskyInterpretation(value)

        case 0o011:                 // [OUTPUT] CH011: Status lamp latches (AGC state indicators)
            if (value & 0b1101111111111101) != 0x0000 {        // if not COMP_ACTY
                logDSKY("011", bitsLabel: "15",
                        value: value, pretty: prettyCh011(value))
            }

            let compVisible = value & DSKY.Ch011.compActivity > 0
            if model.comp.1 != compVisible {
                model.comp.1 = compVisible
                var tally = RelayTransitionTally()
                if compVisible {
                    tally.addClick()
                } else {
                    tally.addOff()
                }
                enqueueRelaySound(for: tally)
            }

            setLamp(.uplinkActivity, to: (value & DSKY.Ch011.uplinkActivity > 0) ? .white  : .off, reason: "CH011")
            setLamp(.tempWarning,    to: (value & DSKY.Ch011.tempWarning    > 0) ? .yellow : .off, reason: "CH011")
            setLamp(.keyRelease,     to: (value & DSKY.Ch011.keyRelease     > 0) ? .white  : .off, reason: "CH011")
            setLamp(.operatorError,  to: (value & DSKY.Ch011.operatorError  > 0) ? .white  : .off, reason: "CH011")

        case 0o013:                 // [OUTPUT] CH013: Lamp test (forces certain lamps on for diagnostics)
            setLamp(.standby, to: (value & DSKY.Ch013.standby > 0) ? .white : .off, reason: "CH013")

        case 0o015:                 // [INPUT] CH015: Keyboard strokes input from DSKY
            // Incoming key presses; used for detecting resets
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

        case 0o077:                 // [OUTPUT] CH077: Hardware restart source code
            logDSKY("077", value: value, note: "H/W RESET")

        case 0o163:                 // [OUTPUT] CH163: Additional lamps + VERB/NOUN flash + EL power control
            // Redundant lamp bits with CH011 (provides extra control)
            // Bit 6 flashes VERB/NOUN displays during entry prompts
            // Bit 10 controls electroluminescent panel power
            logDSKY("163", bitsLabel: "10",
                    value: value, pretty: prettyCh163(value))

            let previousVerbVisible = model.verb.1
            let previousNounVisible = model.noun.1

            setLamp(.tempWarning, to: (value & DSKY.Ch163.tempLamp    > 0) ? .yellow : .off, reason: "CH163")
            setLamp(.keyRelease,  to: (value & DSKY.Ch163.keyRelLamp  > 0) ? .white  : .off, reason: "CH163")
            setLamp(.operatorError, to: (value & DSKY.Ch163.operErrLamp > 0) ? .white  : .off, reason: "CH163")
            setLamp(.restart,     to: (value & DSKY.Ch163.restartLamp > 0) ? .yellow : .off, reason: "CH163")
            setLamp(.standby,     to: (value & DSKY.Ch163.standbyLamp > 0) ? .white  : .off, reason: "CH163")

            let verbNounVisible = value & DSKY.Ch163.verbNounFlash == 0
            model.verb.1 = verbNounVisible
            model.noun.1 = verbNounVisible

            var flashTally = RelayTransitionTally()
            playDisplayVisibilityTransition(value: model.verb.0,
                                            wasVisible: previousVerbVisible,
                                            isVisible: verbNounVisible,
                                            tally: &flashTally)
            playDisplayVisibilityTransition(value: model.noun.0,
                                            wasVisible: previousNounVisible,
                                            isVisible: verbNounVisible,
                                            tally: &flashTally)
            enqueueRelaySound(for: flashTally)

            let newELPowerOn = value & DSKY.Ch163.elPowerOff == 0
            if model.elPowerOn != newELPowerOn {
                logger.log("EL Power: \(newELPowerOn ? "ON" : "OFF") via CH163")

                var powerTally = RelayTransitionTally()
                if newELPowerOn {
                    powerTally.addClick()
                } else {
                    powerTally.addOff()
                }
                enqueueRelaySound(for: powerTally)
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

/// Interpret channel 010 display data and update digit registers.
///
/// PACKET FORMAT: 16-bit word with bit fields for a display row:
/// - Bits 15-11: Row code (identifies which register row)
/// - Bit 10: Sign bit (for ±)
/// - Bits 9-5: C-digit code
/// - Bits 4-0: D-digit code
///
/// Row codes 12 is lamp data; rows 1-11 are register updates.
/// Each digit transition triggers relay tallying for audio simulation.
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
                let oldSign = reg1Bytes[0]
                model.r1Sign.0 = bBit
                reg1Bytes[0] = plu_min(model.r1Sign)
                playDigitTransition(from: oldSign, to: reg1Bytes[0], tally: &relayTally)

                playDigitTransition(from: reg1Bytes[2], to: cStr, tally: &relayTally)
                reg1Bytes[2] = cStr

                playDigitTransition(from: reg1Bytes[3], to: dStr, tally: &relayTally)
                reg1Bytes[3] = dStr
                model.reg1.0 = reg1Bytes.joined()

            case 6:         // "1415" & "R1-"
                let oldSign = reg1Bytes[0]
                model.r1Sign.1 = bBit
                reg1Bytes[0] = plu_min(model.r1Sign)
                playDigitTransition(from: oldSign, to: reg1Bytes[0], tally: &relayTally)

                playDigitTransition(from: reg1Bytes[4], to: cStr, tally: &relayTally)
                reg1Bytes[4] = cStr

                playDigitTransition(from: reg1Bytes[5], to: dStr, tally: &relayTally)
                reg1Bytes[5] = dStr
                model.reg1.0 = reg1Bytes.joined()

            case 5:         // "2122" & "R2+"
                let oldSign = reg2Bytes[0]
                model.r2Sign.0 = bBit
                reg2Bytes[0] = plu_min(model.r2Sign)
                playDigitTransition(from: oldSign, to: reg2Bytes[0], tally: &relayTally)

                playDigitTransition(from: reg2Bytes[1], to: cStr, tally: &relayTally)
                reg2Bytes[1] = cStr

                playDigitTransition(from: reg2Bytes[2], to: dStr, tally: &relayTally)
                reg2Bytes[2] = dStr
                model.reg2.0 = reg2Bytes.joined()

            case 4:         // "2324" & "R2-"
                let oldSign = reg2Bytes[0]
                model.r2Sign.1 = bBit
                reg2Bytes[0] = plu_min(model.r2Sign)
                playDigitTransition(from: oldSign, to: reg2Bytes[0], tally: &relayTally)

                playDigitTransition(from: reg2Bytes[3], to: cStr, tally: &relayTally)
                reg2Bytes[3] = cStr

                playDigitTransition(from: reg2Bytes[4], to: dStr, tally: &relayTally)
                reg2Bytes[4] = dStr
                model.reg2.0 = reg2Bytes.joined()

            case 2:         // "3233" & "R3+"
                let oldSign = reg3Bytes[0]
                model.r3Sign.0 = bBit
                reg3Bytes[0] = plu_min(model.r3Sign)
                playDigitTransition(from: oldSign, to: reg3Bytes[0], tally: &relayTally)

                playDigitTransition(from: reg3Bytes[2], to: cStr, tally: &relayTally)
                reg3Bytes[2] = cStr

                playDigitTransition(from: reg3Bytes[3], to: dStr, tally: &relayTally)
                reg3Bytes[3] = dStr
                model.reg3.0 = reg3Bytes.joined()

            case 1:         // "3435" & "R3-"
                let oldSign = reg3Bytes[0]
                model.r3Sign.1 = bBit
                reg3Bytes[0] = plu_min(model.r3Sign)
                playDigitTransition(from: oldSign, to: reg3Bytes[0], tally: &relayTally)

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

/// Compare two digit strings and record relay transitions for each position that changed.
/// Converts each changed digit position into a click or off event for audio simulation.
private func playDigitTransitions(from oldChars: [Character],
                                  to newDigits: [String],
                                  tally: inout RelayTransitionTally) {
    for (index, newDigit) in newDigits.enumerated() where index < oldChars.count {
        playDigitTransition(from: String(oldChars[index]), to: newDigit, tally: &tally)
    }
}

/// Record a relay transition from one digit/sign to another.
/// - Transition to underscore or space: adds an "off" event (relay disengages)
/// - Transition to numeric digit or sign: adds a "click" event (relay engages)
/// - No change: does nothing
private func playDigitTransition(from oldDigit: String,
                                 to newDigit: String,
                                 tally: inout RelayTransitionTally) {
    guard oldDigit != newDigit else { return }

    if newDigit == "_" || newDigit == " " {
        tally.addOff()
    } else if isDskyRelayOnCharacter(newDigit) {
        tally.addClick()
    }
}

/// Record relay transitions when a display (VERB/NOUN) toggles between visible and invisible.
/// When transitioning from visible to invisible, treats all digits as turning off (underscores).
/// When transitioning from invisible to visible, treats all digits as turning on.
/// This simulates the relay engagement as the display is powered on/off.
private func playDisplayVisibilityTransition(value: String,
                                             wasVisible: Bool,
                                             isVisible: Bool,
                                             tally: inout RelayTransitionTally) {
    guard wasVisible != isVisible else { return }

    let oldChars = Array(wasVisible ? value : "__")
    let newDigits = Array(isVisible ? value : "__").map { String($0) }
    playDigitTransitions(from: oldChars, to: newDigits, tally: &tally)
}

/// Enqueue a relay transition tally to the soundboard for deferred playback.
private func enqueueRelaySound(for tally: RelayTransitionTally) {
    relaySoundboard.enqueue(tally)
}

/// Check if a single character is a decimal digit.
private func isDskyNumericDigit(_ value: String) -> Bool {
    guard value.count == 1, let scalar = value.unicodeScalars.first else { return false }
    return CharacterSet.decimalDigits.contains(scalar)
}

/// Check if a character represents a relay "on" state (numeric digit or sign).
/// Used to distinguish active states from blanks/underscores for audio tallying.
private func isDskyRelayOnCharacter(_ value: String) -> Bool {
    if value == "+" || value == "-" { return true }
    return isDskyNumericDigit(value)
}

/// Emit a debug log entry for DSKY activity with optional binary breakdown and notes.
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

/// Update a status lamp's color and enqueue relay transitions for audio.
///
/// Lamp transitions from off→lit (or vice versa) produce relay sounds.
/// Smooth color transitions (off→red) do not produce sound (no relay engagement).
/// Uses weighted energy based on lamp position: left column lamps contribute less energy.
private func setLamp(_ lamp: StatusLamp,
                     to color: BackColor,
                     reason: String) {
    let index = StatusLamp.index(for: lamp)
    if let current = model.lights[index] {
        if current.1 != color {
            logger.log("""
                Lamp: \(lamp) [\(String(describing: current.1))→\(String(describing: color))] \
                via \(reason)
                """
            )

            let wasLit = current.1 != .off
            let isLit = color != .off
            if wasLit != isLit {
                let weight = lampRelayWeight(for: index)
                var tally = RelayTransitionTally()
                if isLit {
                    tally.addClick(weight: weight)
                } else {
                    tally.addOff(weight: weight)
                }
                enqueueRelaySound(for: tally)
            }
        }
        model.lights[index] = (current.0, color)
    } else {
        logger.error("Missing lamp slot for \(lamp); creating fallback entry")
        model.lights[index] = (lamp.description, color)

        if color != .off {
            let weight = lampRelayWeight(for: index)
            var tally = RelayTransitionTally()
            tally.addClick(weight: weight)
            enqueueRelaySound(for: tally)
        }
    }
}

/// Compute relay weight contribution for a lamp based on physical location.
///
/// APOLLO DSKY ACOUSTIC PROPERTY:
/// Left-column annunciators (indices 11-17) are acoustically softer than right-column lamps
/// due to their position relative to the DSKY's internal acoustics.
/// This simulation models that difference with weighted energy contributions.
private func lampRelayWeight(for index: Int) -> Float {
    // Left column annunciators (11-17: UPLINK, NO ATT, STANDBY, KEY REL, OPR ERR, PRIO DISP, NO DAP)
    // are softer acoustically on the real DSKY.
    if (11...17).contains(index) {
        return LAMP_WEIGHT_LEFT_COLUMN
    }
    return LAMP_WEIGHT_RIGHT_COLUMN
}
