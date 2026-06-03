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

    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
        @AppStorage("alwaysOnTop") private var alwaysOnTop = true

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

        startNetworkOnStartup()
    }

/*╭╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╮
  ┆ do other things as the ContentView runs ..                                                       ┆
  ╰╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╯*/
    var body: some Scene {
        WindowGroup {
            AppView()
        }
        .defaultSize(CGSize(width: model.windowW, height: model.windowH))
        #if os(macOS)
            .defaultPosition(UnitPoint(x: model.windowX, y: model.windowY))
        #endif
/*╭╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╮
  ┆ Menu management ..                                                                               ┆
  ╰╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╯*/
        .commands {
            //CommandGroup(replacing: .pasteboard) { }        // "Cut", "Copy", "Paste", ..
            CommandGroup(replacing: .newItem) { }           // "File" removed ("New", "Open", ..)
            //CommandGroup(replacing: .undoRedo) { }
            CommandGroup(replacing: .systemServices) { }
            CommandGroup(replacing: .windowSize) { }
            CommandGroup(replacing: .windowArrangement) { }
            CommandGroup(after: .windowArrangement) {
                Toggle("Always on Top", isOn: $alwaysOnTop)
                    .keyboardShortcut("p", modifiers: [.command, .option])
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
    #if os(macOS)
        @AppStorage("alwaysOnTop") private var alwaysOnTop = true
    #endif

    var body: some View {
        let scaleFactor = model.fullSize ? 1 : 0.5
        VStack {
            DisKeyView()
                .frame(width: model.windowW, height: model.windowH)        // 569 × 656 pixels
                .scaleEffect(scaleFactor)
            #if os(macOS)
            //ToDo: what if half size no mission/network?
                if model.fullSize && !model.isNetworkConnected {
                    Divider()
                    MonitorView()
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

#Preview("AppView") { AppView() }

struct MonitorView: View {

    @AppStorage("monitor.ipAddr") private var ipAddr: String = "localhost"
    @AppStorage("monitor.ipPort") private var ipPort: Int = 19697
    @AppStorage("monitor.menuString") private var menuString = "Select Mission"

    private var resolvedPort: UInt16? {
        guard let port = UInt16(exactly: ipPort), port > 0 else { return nil }
        return port
    }

    static var integer: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    var body: some View {
        HStack {
            Menu(menuString) {
                Button("Apollo CM 8-17",
                       action: {applyMissionSelection("Apollo CM 8-17")}
                )
                Button("Apollo LM 11-14",
                       action: {applyMissionSelection("Apollo LM 11-14")}
                )
                Button("Apollo LM 15-17",
                       action: {applyMissionSelection("Apollo LM 15-17")}
                )
            }

            TextField("AGC Address", text: $ipAddr)
                .font(.custom("Menlo", size: 12))

            TextField("AGC PortNum", value: $ipPort, formatter: MonitorView.integer)
                .font(.custom("Menlo", size: 12))

/*╭╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╮
  ┆ .. make network connection                                                                       ┆
  ╰╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╯*/
            Button("Connect",
                systemImage: "phone.connection",
                action: {
                    guard let port = resolvedPort else { return }
                    model.ipAddr = ipAddr
                    model.ipPort = port
                    startNetworkForMonitorButton()
                }
            )
            .disabled(ipAddr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || resolvedPort == nil || menuString == "Select Mission")
        }
        .padding(5)
        .background(.gray)
        .onAppear {
            applyMissionSelection(menuString)
        }
    }

    private func applyMissionSelection(_ selection: String) {
        if applyMissionSelectionToModel(selection) {
            menuString = selection
        }
    }
}

#if swift(>=5.9)
#Preview("Monitor") { MonitorView() }
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
        //model.network = Network("192.168.1.232", 19697)                 // .. Ubuntu
        model.network = Network("192.168.1.100", 19697)                 // .. MaxBook
        //model.network = Network("192.168.1.192", 19697)                 // .. iPhone
        //model.network = Network("192.168.1.228", 19697)                 // .. iPadM4
        //model.network = Network("127.0.0.1",     19697)                 // .. localhost
        model.network.start()
        updateELPowerFromNetwork(reason: "iOS/tvOS startup")
        model.network.startDSKYReceiveLoop()
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

// Checks if ipAddr, ipPort & mission selection are valid and present
// Aplies the selected mission configuration to the model
private func hasConnectData() -> Bool {
    let hasAddress = !model.ipAddr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let hasPort = model.ipPort > 0
    let menuValue = UserDefaults.standard.string(forKey: "monitor.menuString")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let hasMission = !menuValue.isEmpty && menuValue != "Select Mission"
    if hasMission {
        applyMissionSelectionToModel(menuValue)
    }

    return hasAddress && hasPort && hasMission
}
#endif

private func updateELPowerFromNetwork(reason: String) {
    let connected = model.network.connection.state == .ready

    if model.elPowerOn != connected {
        logger.log("EL Power: \(connected ? "ON" : "OFF") via \(reason)")
        model.elPowerOn = connected
    }
}

@discardableResult
private func applyMissionSelectionToModel(_ selection: String) -> Bool {
    switch selection {
        case "Apollo CM 8-17":
            model.cmLamps()
            return true
        case "Apollo LM 11-14":
            model.lm0Lamps()
            return true
        case "Apollo LM 15-17":
            model.lm1Lamps()
            return true
        default:
            return false
    }
}
