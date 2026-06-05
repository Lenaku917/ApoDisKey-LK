//
//  DisKeyApp.swift
//  ApoDisKey
//
//  Created by Gavin Eadie on Jul06/24 (copyright 2024-25)
//

import SwiftUI
import OSLog

let logger = Logger(subsystem: "com.ramsaycons.ApoDisKey", category: "main")

nonisolated(unsafe) let model = DisKeyModel.shared

@main
struct DisKeyApp: App {
    @AppStorage("audioMutedAll") private var audioMutedAll = false
    @AppStorage("audioSyncTimeS") private var audioSyncTimeS = 0.006
    @AppStorage("audioRelayClicksMuted") private var audioRelayClicksMuted = false
    @AppStorage("audioButtonPressMuted") private var audioButtonPressMuted = false
    @AppStorage("alwaysOnTop") private var alwaysOnTop = true
    @AppStorage("mission") private var mission: Mission = .cm8_17
    @AppStorage("ipAddr") private var ipAddr: String = "localhost"
    @AppStorage("ipPort") private var ipPort: Int = 19697

    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

        class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
            func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

            func applicationDidFinishLaunching(_ notification: Notification) {
                let enabled = UserDefaults.standard.object(forKey: "alwaysOnTop") as? Bool ?? true
                DispatchQueue.main.async {
                    applyAlwaysOnTopWindowLevel(enabled)
                }
            }

        }
    #endif

/*╭╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╮
  ┆ establish the global environment                                                                 ┆
  ╰╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╯*/
    init() {
        model.windowW = CGFloat(569)
        model.windowH = CGFloat(656)

        #if os(macOS)
            extractOptions()                        // get any command arguments ..
        #endif

        applyStoredSettingsToModel()
        startNetworkOnStartup()
    }

/*╭╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╮
  ┆ do other things as the ContentView runs ..                                                       ┆
  ╰╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╯*/
    var body: some Scene {
        WindowGroup {
            AppView(audioMutedAll: $audioMutedAll, audioSyncTimeS: $audioSyncTimeS, audioRelayClicksMuted: $audioRelayClicksMuted, audioButtonPressMuted: $audioButtonPressMuted, alwaysOnTop: $alwaysOnTop, mission: $mission, ipAddr: $ipAddr, ipPort: $ipPort)
        }
        .defaultSize(CGSize(width: model.windowW, height: model.windowH))
        #if os(macOS)
            .defaultPosition(UnitPoint(x: model.windowX, y: model.windowY))
        #endif
/*╭╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╮
  ┆ Menu management ..                                                                               ┆
  ╰╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╯*/
        .commands {
            CommandGroup(replacing: .newItem) { }           // "File" removed ("New", "Open", ..)
            //CommandGroup(replacing: .pasteboard) { }        // "Cut", "Copy", "Paste", ..
            //CommandGroup(replacing: .undoRedo) { }
            CommandGroup(replacing: .systemServices) { }
            CommandGroup(replacing: .windowSize) { }
            CommandGroup(replacing: .windowArrangement) { }
            CommandMenu("Settings") {
                SettingsMenuContent(audioMutedAll: $audioMutedAll, audioSyncTimeS: $audioSyncTimeS, audioRelayClicksMuted: $audioRelayClicksMuted, audioButtonPressMuted: $audioButtonPressMuted, alwaysOnTop: $alwaysOnTop, mission: $mission, ipAddr: $ipAddr, ipPort: $ipPort)
            }
            #if os(macOS)
                CommandGroup(replacing: .help) {
                    Button("ApoDisKey Help") { openHelpWindow() }
                    Button("ApoDisKey News") { openNewsWindow() }
                }
            #endif
        }
    }

    #if os(macOS)
        @State private var helpWindowController: HelpWindowController?
        @State private var newsWindowController: NewsWindowController?

        private func openHelpWindow() {
            if helpWindowController == nil {
                helpWindowController = HelpWindowController()
            }
            helpWindowController?.showWindow(nil)
            helpWindowController?.window?.makeKeyAndOrderFront(nil)
            helpWindowController?.window?.level = alwaysOnTop ? .floating : .normal
        }

        private func openNewsWindow() {
            if newsWindowController == nil {
                newsWindowController = NewsWindowController()
            }
            newsWindowController?.showWindow(nil)
            newsWindowController?.window?.makeKeyAndOrderFront(nil)
            newsWindowController?.window?.level = alwaysOnTop ? .floating : .normal
        }
    #endif

}

struct AppView: View {
    @Binding var audioMutedAll: Bool
    @Binding var audioSyncTimeS: Double
    @Binding var audioRelayClicksMuted: Bool
    @Binding var audioButtonPressMuted: Bool
    @Binding var alwaysOnTop: Bool
    @Binding var mission: Mission
    @Binding var ipAddr: String
    @Binding var ipPort: Int

    var body: some View {
        let scaleFactor = model.fullSize ? 1 : 0.5
        VStack {
            DisKeyView()
                .frame(width: model.windowW, height: model.windowH)        // 569 × 656 pixels
                .scaleEffect(scaleFactor)
                #if os(macOS)
                    .contextMenu {
                        SettingsMenuContent(audioMutedAll: $audioMutedAll, audioSyncTimeS: $audioSyncTimeS, audioRelayClicksMuted: $audioRelayClicksMuted, audioButtonPressMuted: $audioButtonPressMuted, alwaysOnTop: $alwaysOnTop, mission: $mission, ipAddr: $ipAddr, ipPort: $ipPort)
                    }
                #endif
            #if os(macOS)
            //ToDo: what if half size no mission/network?
                if model.fullSize && !model.isNetworkConnected {
                    Divider()
                    MonitorView(mission: $mission, ipAddr: $ipAddr, ipPort: $ipPort)
                }
            #endif
        }
        #if os(macOS)
            .onChange(of: alwaysOnTop) { _, newValue in
                applyAlwaysOnTopWindowLevel(newValue)
            }
        #endif
    }
}

#Preview("AppView") { AppView(audioMutedAll: .constant(false), audioSyncTimeS: .constant(0.006), audioRelayClicksMuted: .constant(false), audioButtonPressMuted: .constant(false), alwaysOnTop: .constant(true), mission: .constant(.cm8_17), ipAddr: .constant("localhost"), ipPort: .constant(19697)) }

struct MonitorView: View {

    @AppStorage("monitor.ipAddr") private var mIpAddr: String = model.ipAddr
    @AppStorage("monitor.ipPort") private var mIpPort: Int = model.ipPort
    @Binding var mission: Mission
    @Binding var ipAddr: String
    @Binding var ipPort: Int

    private var resolvedPort: Int? {
        guard mIpPort > 0 else { return nil }
        return mIpPort
    }

    static var integer: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    var body: some View {
        HStack {
            MissionMenu(mission: $mission)

            TextField("AGC Address", text: $mIpAddr)
                .font(.custom("Menlo", size: 12))

            TextField("AGC PortNum", value: $mIpPort, formatter: MonitorView.integer)
                .font(.custom("Menlo", size: 12))

/*╭╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╮
  ┆ .. make network connection                                                                       ┆
  ╰╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╯*/
            Button("Connect",
                systemImage: "phone.connection",
                action: {
                    guard let port = resolvedPort else { return }
                    ipAddr = mIpAddr
                    ipPort = mIpPort
                    model.ipAddr = ipAddr
                    model.ipPort = port
                    startNetworkForMonitorButton()
                }
            )
            .disabled(mIpAddr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || resolvedPort == nil)
        }
        .padding(5)
        .background(.gray)
        /* .onAppear {
            setMission(model.mission)
        } */
    }

    /* private func setMission(_ newMission: Mission) {
        model.mission = newMission
    } */

}

#if swift(>=5.9)
#Preview("Monitor") { MonitorView(mission: .constant(.cm8_17), ipAddr: .constant("localhost"), ipPort: .constant(19697)) }
#endif

#if os(macOS)
@MainActor
private func applyAlwaysOnTopWindowLevel(_ enabled: Bool) {
    let level: NSWindow.Level = enabled ? .floating : .normal
    for window in NSApplication.shared.windows where window.styleMask.contains(.titled) {
        window.level = level
    }
    logger.log("Window always-on-top: \(enabled ? "ON" : "OFF")")
}
#endif

#if os(macOS)
private enum NetworkConnectTrigger {
    case startup
    case monitorButton
    case dskyKeyPress

    var reason: String {
        switch self {
            case .startup: return "startUp"
            case .monitorButton: return "ConnectBtn"
            case .dskyKeyPress: return "DSKY Key Press"
        }
    }
}

func startNetworkOnStartup() {

    #if os(macOS)
        startNetwork(trigger: .startup)

    //ToDo: check if non mac stuff works
    #elseif os(iOS) || os(tvOS)
        model.statusLights = DisKeyModel.lunarModule0
        model.ipPort = 19697
        model.ipAddr = "192.168.1.100"                  // .. MaxBook
        // model.ipAddr = "192.168.1.232"               // .. Ubuntu
        // model.ipAddr = "192.168.1.192"               // .. iPhone
        // model.ipAddr = "192.168.1.228"               // .. iPadM4
        // model.ipAddr = "127.0.0.1"                   // .. localhost

        startNetwork(trigger: .startup)
        updateELPowerFromNetwork(reason: "iOS/tvOS startup")
    #endif

}

func startNetworkForMonitorButton() {
    startNetwork(trigger: .monitorButton)
}

func startNetworkForDSKYKeyPress() {
    startNetwork(trigger: .dskyKeyPress)
}

// Starts network connection if ipAddr, ipPort & mission are set.
// Also applies the selected mission configuration to the model
private func startNetwork(trigger: NetworkConnectTrigger) {


    //Apply mission to model
    if trigger == .startup {
        switch model.mission {
            case .cm8_17: model.cmLamps()
            case .lm11_14: model.lm0Lamps()
            case .lm15_17: model.lm1Lamps()
        }
    }

    if hasConnectData() {
        logger.log("""
            →→→ startNetwork via \(trigger.reason): \
            ipAddr=\(model.ipAddr, privacy: .public), \
            ipPort=\(model.ipPort, privacy: .public)
            """)
        model.network = Network(model.ipAddr, model.ipPort)
        model.network.start()
        updateELPowerFromNetwork(reason: trigger.reason)

        if trigger == .monitorButton {
            model.network.sendDSKY032ReadyFromMonitor()
        }

    }

    model.network.startDSKYReceiveLoop()
}

private func isConnected() -> Bool {
    return model.isNetworkConnected
}

// Checks if ipAddr, ipPort & mission selection are valid and present
// Aplies the selected mission configuration to the model
private func hasConnectData() -> Bool {
    let hasAddress = !model.ipAddr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let hasPort = model.ipPort > 0

    return hasAddress && hasPort
}
#endif

private func updateELPowerFromNetwork(reason: String) {
    let connected = model.network.connection.state == .ready

    if model.elPowerOn != connected {
        logger.log("EL Power: \(connected ? "ON" : "OFF") via \(reason)")
        model.elPowerOn = connected
    }
}


#if os(macOS)
private extension DisKeyApp {
    func applyStoredSettingsToModel() {
        model.audioMutedAll = audioMutedAll
        model.audioSyncTimeS = audioSyncTimeS
        model.audioRelayClicksMuted = audioRelayClicksMuted
        model.audioButtonPressMuted = audioButtonPressMuted
        model.mission = mission
        model.ipAddr = ipAddr
        model.ipPort = ipPort
    }
}
#endif

struct MissionMenu: View {
    @Binding var mission: Mission

    var body: some View {
        Menu("Mission: \(mission.rawValue)") {
            ForEach(Mission.allCases, id: \.self) { option in
                Button(option == mission ? "✔︎ \(option.rawValue)" : option.rawValue) {
                    model.mission = option
                    mission = option
                }
            }
        }
    }
}


struct SettingsMenuContent: View {
    @Binding var audioMutedAll: Bool
    @Binding var audioSyncTimeS: Double
    @Binding var audioRelayClicksMuted: Bool
    @Binding var audioButtonPressMuted: Bool
    @Binding var alwaysOnTop: Bool
    @Binding var mission: Mission
    @Binding var ipAddr: String
    @Binding var ipPort: Int

    var body: some View {
        Button(audioMutedAll ? "🔇 Unmute Audio" : "🔊 Mute Audio") {
            model.audioMutedAll.toggle()
            audioMutedAll = model.audioMutedAll
        }
        .keyboardShortcut("m", modifiers: [.command])

        Toggle("Button Press", isOn: Binding(
            get: { !audioButtonPressMuted },
            set: { model.audioButtonPressMuted = !$0; audioButtonPressMuted = !$0 }
        )) .disabled(model.audioMutedAll)

        Toggle("Relay Clicks", isOn: Binding(
            get: { !audioRelayClicksMuted },
            set: { model.audioRelayClicksMuted = !$0; audioRelayClicksMuted = !$0 }
        )) .disabled(model.audioMutedAll)

        Text("Relay Sync Delay: \(audioSyncTimeS * 1000, specifier: "%.0f")ms")

        Button(" +  Increase") {
            let next = min(0.1, audioSyncTimeS + 0.001)
            model.audioSyncTimeS = next
            audioSyncTimeS = next
        } .disabled(audioMutedAll || audioSyncTimeS >= 0.1)
        .keyboardShortcut("+", modifiers: [.command])

        Button(" -  Decrease") {
            let next = max(0.001, audioSyncTimeS - 0.001)
            model.audioSyncTimeS = next
            audioSyncTimeS = next
        } .disabled(audioMutedAll || audioSyncTimeS <= 0.001)
        .keyboardShortcut("-", modifiers: [.command])

        Button(" +  Increase (x10)") {
            let next = min(0.1, model.audioSyncTimeS + 0.01)
            model.audioSyncTimeS = next
            audioSyncTimeS = next
        } .disabled(model.audioMutedAll || model.audioSyncTimeS >= 0.1)
        .keyboardShortcut("+", modifiers: [.shift, .command])

        Button(" -  Decrease (x10)") {
            let next = max(0.001, model.audioSyncTimeS - 0.01)
            model.audioSyncTimeS = next
            audioSyncTimeS = next
        } .disabled(model.audioMutedAll || model.audioSyncTimeS <= 0.001)
        .keyboardShortcut("-", modifiers: [.shift, .command])

        Divider()

        Text("\(ipAddr) : \(String(ipPort))")

        Button("Dis-/Connect") { // Can't use isConnected()? bc it will make the mission menu flicker...
             if isConnected() {
                model.network.stop()
                updateELPowerFromNetwork(reason: "Settings Disconnect")
             } else {
                startNetworkForMonitorButton()
             }
        }

        // Mission
        MissionMenu(mission: $mission)

        Divider()

        Toggle("Always on Top", isOn: $alwaysOnTop)
        .keyboardShortcut("p", modifiers: [.command])
    }

}
