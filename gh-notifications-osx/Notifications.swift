//
//  Notifications.swift
//  gh-notifications-osx
//
//  Created by Dmytro Milinevskyi on 10/01/2022.
//

import AppKit
import ArgumentParser
import Foundation
import OctoKit
import os
import Puppy
import RealmSwift
import RequestKit
import SwiftUI
import UserNotifications

let GitHubApiTokenName = "GitHub API token for notifications"

struct Args: ParsableArguments {
    @Flag(help: "Enable debug output of the requests tracer.")
    var traceRequests = false

    @Option(help: "Refresh period (in seconds).")
    var refreshPeriod: Double = 60.0

    @Option(help: "Notification period (in seconds).")
    var notificationPeriod: Double = 3600.0
}

let args = Args.parseOrExit()

public struct CustomTokenConfiguration: Configuration {
    public var apiEndpoint: String = githubBaseURL
    public var cachePolicy: NSURLRequest.CachePolicy = .reloadIgnoringLocalCacheData
    public var accessToken: String?
    public let errorDomain = OctoKitErrorDomain
    public let authorizationHeader: String? = "token"
    public var tracerConfiguration: TracerConfiguration?

    public var customHeaders: [HTTPHeader]? = [
        HTTPHeader(headerField: "cache-control", value: "no-cache"),
    ]

    public init(_ token: String? = nil) {
        accessToken = token
        if args.traceRequests {
            tracerConfiguration = [.RequestHeaders, .ResponseHeaders]
        }
    }
}

// Realm could not be passed between threads, so should always be created localy with
// var realm = try! Realm()

class GHNotification: Object {
    @Persisted var id: String
    @Persisted var title: String
}

class GHNotificationsUpdate: Object {
    @Persisted(primaryKey: true) var id = 0
    @Persisted var date: Date
}

extension String: Error {}

class Notifications: NSObject, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var error: Error?
    let logger = Puppy.default

    override init() {
        super.init()

        let bundleId = Bundle.main.bundleIdentifier ?? "gh-notifications-osx"
        Puppy.default.add(OSLogger("os", category: "notifications"))
        do {
            let logPath = URL(fileURLWithPath: "Library/Logs/\(bundleId).log")
            let fileRotation = try FileRotationLogger("file", fileURL: logPath)
            fileRotation.maxFileSize = 10 * 1024 * 1024
            fileRotation.maxArchivedFilesCount = 5
            class LogFormatter: LogFormattable {
                func formatMessage(_ level: LogLevel, message: String, tag _: String, function: String,
                                   file: String, line: UInt, swiftLogInfo _: [String: String],
                                   label _: String, date: Date, threadID: UInt64) -> String
                {
                    let date = dateFormatter(date)
                    let file = shortFileName(file)
                    return "\(date) \(threadID) [\(level.emoji) \(level)] \(file)#L.\(line) \(function) \(message)"
                }
            }
            fileRotation.format = LogFormatter()
            Puppy.default.add(fileRotation)
            os_log("Log path: '\(logPath)'")
        } catch {
            os_log("Failed to init file logger: \(error.localizedDescription)")
        }
    }

    func run(contentView: ContentView) {
        if statusItem != nil {
            logger.error("Double invocation? Should not happen!")
            return
        }
        logger.info("Started GitHub notifications notifier: '\(Bundle.main.bundleIdentifier ?? "?")'")
        logger.info("Realm DB path: \(Realm.Configuration.defaultConfiguration.fileURL!.absoluteString)")

        hideFromDock()

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error = error {
                self.logger.error("Failed to request authorization: '\(error.localizedDescription)'")
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "?"
        statusItem?.button?.action = #selector(onClick(_:))
        statusItem?.button?.target = self

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)

        ghNotificationsSafe()
        Timer.scheduledTimer(withTimeInterval: args.refreshPeriod, repeats: true) { _ in
            self.ghNotificationsSafe()
        }
    }

    func getGitHubToken() throws -> String {
        let query: [String: AnyObject] = [
            kSecAttrService as String: GitHubApiTokenName as AnyObject,
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: kCFBooleanTrue,
        ]
        var itemCopy: AnyObject?
        _ = SecItemCopyMatching(
            query as CFDictionary,
            &itemCopy
        )
        guard let password = itemCopy as? Data else {
            throw "Can't find \(GitHubApiTokenName)"
        }
        return String(decoding: password, as: UTF8.self)
    }

    func hideFromDock() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.prohibited)
        }
    }

    func markErrorMaybe() {
        if error == nil {
            return
        }
        DispatchQueue.main.async {
            self.statusItem?.button?.attributedTitle = NSAttributedString(string: "☠", attributes: [NSAttributedString.Key.foregroundColor: NSColor.red])
        }
    }

    @objc func onClick(_: AnyObject?) {
        if let error = error {
            DispatchQueue.main.async {
                let txt = NSTextField(string: "Runtime error: '\(error.localizedDescription)'")
                self.popover.contentViewController!.view = txt
                self.popover.show(relativeTo: self.statusItem!.button!.bounds, of: self.statusItem!.button!, preferredEdge: NSRectEdge.maxY)
            }
        } else {
            let url = "https://github.com/notifications?query=reason%3Aparticipating+is%3Aunread"
            Process.launchedProcess(launchPath: "/usr/bin/open", arguments: [url])
        }
    }

    func notify(_ newNotifications: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(newNotifications) new notifications"
        content.body = "Check them out!"
        let uuid = UUID().uuidString
        let request = UNNotificationRequest(identifier: uuid, content: content, trigger: nil)
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
        notificationCenter.add(request) { error in
            if let error = error {
                self.logger.error("Failed to deliver notification: '\(error.localizedDescription)'")
            }
        }
    }

    func userNotificationCenter(_: UNUserNotificationCenter, didReceive _: UNNotificationResponse, withCompletionHandler: () -> Void) {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            let activationPolicy = NSApp.activationPolicy()
            if activationPolicy == .prohibited {
                timer.invalidate()
                return
            }
            self.logger.debug("Activation policy was altered: '\(activationPolicy)'")
            self.hideFromDock()
        }
        withCompletionHandler()
    }

    func showDelta(_ notifications: [NotificationThread]) throws {
        let realm = try Realm()
        let now = Date()
        if let date = realm.object(ofType: GHNotificationsUpdate.self, forPrimaryKey: 0) {
            let diff = date.date.distance(to: now)
            if diff < args.notificationPeriod {
                return
            }
        }
        let prevNotifications = Set(realm.objects(GHNotification.self).map { notification -> String in notification.id })
        try realm.write {
            realm.delete(realm.objects(GHNotification.self))
        }
        var newNotifications = 0
        for n in notifications {
            if !prevNotifications.contains(n.id!) {
                newNotifications += 1
            }
            try realm.write {
                realm.add(GHNotification(value: ["id": n.id!, "title": n.subject.title!]))
            }
        }
        if newNotifications > 0 {
            notify(newNotifications)
            logger.debug("\(newNotifications) new notifications.")
        }
        try realm.write {
            realm.add(GHNotificationsUpdate(value: ["id": 0, "date": now]), update: .modified)
        }
    }

    func ghNotificationsSafe() {
        error = nil
        defer { markErrorMaybe() }
        do {
            try ghNotifications()
        } catch {
            self.error = error
            logger.error("Failed to fetch GitHub notifications '\(error.localizedDescription)'")
        }
    }

    func ghNotifications() throws {
        let token = try getGitHubToken()
        let config = CustomTokenConfiguration(token)
        let maxPerPage = 20
        Octokit(config).myNotifications(all: false, participating: true, perPage: "\(maxPerPage)") { response in
            switch response {
            case let .success(notifications):
                self.logger.debug("Got \(notifications.count) notifications")
                for n in notifications {
                    self.logger.debug("  > \(n.id!) -> \(n.subject.title!)")
                }
                var title = "\(notifications.count)"
                if notifications.count == maxPerPage {
                    title = "\(notifications.count)"
                }
                var attributes: [NSAttributedString.Key: Any] = [:]
                if notifications.count > 0 {
                    attributes[NSAttributedString.Key.foregroundColor] = NSColor.red
                }
                DispatchQueue.main.async {
                    self.statusItem?.button?.attributedTitle = NSAttributedString(string: title, attributes: attributes)
                }
                do {
                    try self.showDelta(notifications)
                } catch {
                    self.logger.error("Failed to show GitHub notifications delta: '\(error.localizedDescription)'")
                }
            case let .failure(error):
                self.error = error
            }
        }
    }
}
