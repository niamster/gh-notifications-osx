#  What is it?

It's a very basic `GitHub` notifier that sits in the status bar and gently notifies the user when there are any new notifications to the subscribed entities (like PRs, etc.).

Before the launch one should create a [GitHub token](https://github.com/settings/tokens) and add it to the macOS Keychain as `GitHub API token for notifications`:

![GH-API-token-in-the-Keychain](https://user-images.githubusercontent.com/211000/148858206-0b571be7-5665-4870-a8f6-26a2a371583a.png)

On the badge click, the app opens your favourite browser to show pending notifications on [GitHub](https://github.com/notifications?query=reason%3Aparticipating+is%3Aunread).

To enable macOS notifications you might need to explicitly enable them in system preferences, see [this](https://support.apple.com/en-us/HT204079):
![Preferences->Notifications](https://user-images.githubusercontent.com/211000/149068848-fb0239c0-4976-43ea-a556-2aa5c784d1ea.png)


Since this is a perfect application it does not give you a way to quit it. If you really want to stop it, you should show no mercy and kill it, for example with `pkill -f gh-notifications-osx.app`.

Good luck!

# How to build?

Use Xcode, and run `Product->Run` to execute, or `Product->Archive` to create a "release" version of the app.

You can use `Window->Organizer->Archives` to view all available archives.

To export an archive as a local app chose `Distribute App->Copy App`.

# Where to find logs?

The logs should be available in the OS log as well as in file at `~/Library/Containers/gh.gh-notifications-osx/Data/Library/Logs`.
