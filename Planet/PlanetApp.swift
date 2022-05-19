//
//  PlanetApp.swift
//  Planet
//
//  Created by Kai on 2/15/22.
//

import SwiftUI


@main
struct PlanetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var planetStore: PlanetStore
    @StateObject var templateStore: TemplateBrowserStore
    @Environment(\.openURL) private var openURL

    init() {
        self._planetStore = StateObject(wrappedValue: PlanetStore.shared)
        self._templateStore = StateObject(wrappedValue: TemplateBrowserStore.shared)
    }

    var body: some Scene {
        WindowGroup {
            PlanetMainView()
                .environmentObject(planetStore)
                .environment(\.managedObjectContext, PlanetDataController.shared.persistentContainer.viewContext)
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "Planet"))
        .commands {
            CommandGroup(replacing: .newItem) {
            }
            CommandMenu("Planet") {
                Button {
                    if let url = URL(string: "planet://Template") {
                        openURL(url)
                    }
                } label: {
                    Text("Template Browser")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button {
                    PlanetManager.shared.publishLocalPlanets()
                } label: {
                    Text("Publish My Planets")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button {
                    PlanetManager.shared.updateFollowingPlanets()
                } label: {
                    Text("Update Following Planets")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button {
                    planetStore.isImportingPlanet = true
                } label: {
                    Text("Import Planet")
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button {
                    guard planetStore.currentPlanet != nil else { return }
                    planetStore.isExportingPlanet = true
                } label: {
                    Text("Export Planet")
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            SidebarCommands()
            TextEditingCommands()
            TextFormattingCommands()
        }

        WindowGroup("Planet Templates") {
            TemplateBrowserView()
                .environmentObject(templateStore)
                .frame(minWidth: 720, minHeight: 480)
                .handlesExternalEvents(preferring: Set(arrayLiteral: "Template"), allowing: Set(arrayLiteral: "Template"))
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "Template"))

    }
}


class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if url.absoluteString.hasPrefix("planet://") {
            let url = url.absoluteString.replacingOccurrences(of: "planet://", with: "")
            guard !PlanetDataController.shared.planetExists(planetURL: url) else { return }
            // TODO: can this URL be .eth or even a feed?
            let _ = PlanetDataController.shared.createPlanet(withID: UUID(), name: "", about: "", keyName: nil, keyID: nil, ipns: url)
            PlanetDataController.shared.save()
        } else if url.lastPathComponent.hasSuffix(".planet") {
            DispatchQueue.main.async {
                PlanetManager.shared.importPath = url
                PlanetManager.shared.importCurrentPlanet()
            }
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        PlanetDataController.shared.cleanupDatabase()
        let _ = PlanetManager.shared
        TemplateBrowserStore.shared.loadTemplates()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appDidWakeUpAction), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appWillSleepAction), name: NSWorkspace.willSleepNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        PlanetDataController.shared.cleanupDatabase()
        PlanetDataController.shared.save()
        Task.init {
            await IPFSDaemon.shared.shutdownDaemon()
            await NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}


extension AppDelegate {
    @objc
    private func appDidWakeUpAction() {
        // Reactivate timers
    }

    @objc
    private func appWillSleepAction() {
        // Invalidate timers

        // Pause media playback if needed.
        NotificationCenter.default.post(name: .pauseMedia, object: nil)
    }
}
