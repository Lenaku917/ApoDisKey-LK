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
nonisolated(unsafe) private var networkReceiveTask: Task<Void, Never>?

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

    init() {

/*╭╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╮
  ┆ establish the global environment                                                                 ┆
  ╰╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╯*/
        model.windowW = CGFloat(569)
        model.windowH = CGFloat(656)

#if os(macOS)
        extractOptions()                        // get any command arguments ..
#endif

        startNetwork()
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
            CommandGroup(replacing: .pasteboard) { }        // "Cut", "Copy", "Paste", ..
            CommandGroup(replacing: .newItem) { }           // "File" removed ("New", "Open", ..)
            CommandGroup(replacing: .undoRedo) { }
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
                       action: {
                    applyMissionSelection("Apollo CM 8-17")
                })
                Button("Apollo LM 11-14",
                       action: {
                    applyMissionSelection("Apollo LM 11-14")
                })
                Button("Apollo LM 15-17",
                       action: {
                    applyMissionSelection("Apollo LM 15-17")
                })
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
                logger.log("""
                    →→→ monitor set: \
                    ipAddr=\(ipAddr, privacy: .public), \
                    ipPort=\(port, privacy: .public)
                    """)
                startNetwork(connectFromMonitor: true)
            } )
            .disabled(ipAddr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || resolvedPort == nil || menuString == "Select Mission")
        }
        .padding(5)
        .background(.gray)
        .onAppear {
            applyMissionSelection(menuString)
        }
    }

    private func applyMissionSelection(_ selection: String) {
        switch selection {
            case "Apollo CM 8-17":
                model.cmLamps()
                menuString = selection
            case "Apollo LM 11-14":
                model.lm0Lamps()
                menuString = selection
            case "Apollo LM 15-17":
                model.lm1Lamps()
                menuString = selection
            default:
                break
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

func startNetwork(connectFromMonitor: Bool = false) {
/*╭╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╮
  ┆ if command arguments for network are good, use them ..                                           ┆
  ╰╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╯*/
#if os(macOS)
    if model.haveCmdArgs || connectFromMonitor {
        logger.log("""
            →→→ cmdArgs set: \
            ipAddr=\(model.ipAddr, privacy: .public), \
            ipPort=\(model.ipPort, privacy: .public)
            """)
        model.network = Network(model.ipAddr, model.ipPort)
        model.network.start()
        updateELPowerFromNetwork(reason: connectFromMonitor ? "Monitor Connect" : "cmdArgs")

        if connectFromMonitor {
            Task {
                let value: UInt16 = 0b0010_0000_0000_0000
                do {
                    try await model.network.send(formIoPacket(0o0232, value))
                    logger.log("«««    DSKY 032:    \(zeroPadWord(value)) BITS (15)")
                } catch {
                    logger.error("\(error.localizedDescription)")
                    model.elPowerOn = false
                }
            }
        }
    }
#endif

#if os(iOS) || os(tvOS)
    model.statusLights = DisKeyModel.lunarModule0
//  model.network = Network("192.168.1.232", 19697)                 // .. Ubuntu
    model.network = Network("192.168.1.100", 19697)                 // .. MaxBook
//  model.network = Network("192.168.1.192", 19697)                 // .. iPhone
//  model.network = Network("192.168.1.228", 19697)                 // .. iPadM4
//  model.network = Network("127.0.0.1",     19697)                 // .. localhost
    model.network.start()
    updateELPowerFromNetwork(reason: "iOS/tvOS startup")
#endif

    guard model.network.connection.state == .ready else { return }

    networkReceiveTask?.cancel()
    networkReceiveTask = Task {
        while !Task.isCancelled {
            do {
                let (channel, action, _) = try parseIoPacket(try await model.network.receive(length: 4))
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

private func updateELPowerFromNetwork(reason: String) {
    let connected = model.network.connection.state == .ready

    if model.elPowerOn != connected {
        logger.log("EL Power: \(connected ? "ON" : "OFF") via \(reason)")
        model.elPowerOn = connected
    }
}
