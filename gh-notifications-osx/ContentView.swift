//
//  ContentView.swift
//  gh-notifications-osx
//
//  Created by Dmytro Milinevskyi on 10/01/2022.
//

import SwiftUI

struct ContentView: View {
    var notifications = Notifications()

    var body: some View {
        notifications.run()
        return Text("")
    }
}
