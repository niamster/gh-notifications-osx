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
import RealmSwift
import RequestKit
import UserNotifications

let GitHubApiTokenName = "GitHub API token for notifications"

struct Args: ParsableArguments {
    @Flag(help: "Enable debug output.")
    var debug = false

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
// This opens local DB at file:///Users/[User]/Library/Application Support/gh-osx-notifications/default.realm

class GHNotification: Object {
    @Persisted var id: String
    @Persisted var title: String
}

class GHNotificationsUpdate: Object {
    @Persisted(primaryKey: true) var id = 0
    @Persisted var date: Date
}

extension String: Error {}

class Notifications {
    var statusItem: NSStatusItem!

    init() {
        NSApp.setActivationPolicy(.prohibited)

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error = error {
                print("Failed to request authorization: \(error)")
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "?"
        statusItem?.button?.action = #selector(openWebApp(_:))
        statusItem?.button?.target = self
    }

    func run() {
        ghNotifications()
        Timer.scheduledTimer(withTimeInterval: args.refreshPeriod, repeats: true) { _ in
            self.ghNotifications()
        }
    }

    func readPassword() throws -> String {
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

    @objc func openWebApp(_: AnyObject?) {
        let url = "https://github.com/notifications?query=reason%3Aparticipating+is%3Aunread"
        Process.launchedProcess(launchPath: "/usr/bin/open", arguments: [url])
    }

    func notify(_ newNotifications: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(newNotifications) new notifications"
        content.body = "Check them out!"
        let uuidString = UUID().uuidString
        let request = UNNotificationRequest(identifier: uuidString,
                                            content: content, trigger: nil)
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to deliver notification: \(error)")
            }
        }
    }

    func showDelta(_ notifications: [NotificationThread]) {
        let realm = try! Realm()
        let now = Date()
        if let date = realm.object(ofType: GHNotificationsUpdate.self, forPrimaryKey: 0) {
            let diff = date.date.distance(to: now)
            if diff < args.notificationPeriod {
                return
            }
        }
        let prevNotifications = Set(realm.objects(GHNotification.self).map { notification -> String in notification.id })
        try! realm.write {
            realm.delete(realm.objects(GHNotification.self))
        }
        var newNotifications = 0
        for n in notifications {
            if !prevNotifications.contains(n.id!) {
                newNotifications += 1
            }
            try! realm.write {
                realm.add(GHNotification(value: ["id": n.id!, "title": n.subject.title!]))
            }
        }
        if newNotifications > 0 {
            notify(newNotifications)
            if args.debug {
                print("\(newNotifications) new notifications.")
            }
        }
        try! realm.write {
            realm.add(GHNotificationsUpdate(value: ["id": 0, "date": now]), update: .modified)
        }
    }

    func ghNotifications() {
        // Generate new token here https://github.com/settings/tokens
        let token = try! readPassword()
        let config = CustomTokenConfiguration(token)
        let maxPerPage = 20
        Octokit(config).myNotifications(all: false, participating: true, perPage: "\(maxPerPage)") { response in
            switch response {
            case let .success(notifications):
                if args.debug {
                    print("Got \(notifications.count) notifications")
                    for n in notifications {
                        print("  > \(n.id!) -> \(n.subject.title!)")
                    }
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
                self.showDelta(notifications)
            case let .failure(error):
                print(error)
            }
        }
    }
}
