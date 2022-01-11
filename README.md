#  What is it?

It's a very basic `GitHub` notifier that sits in the status bar and gently notifies the user when there are any new notifications to the subscribed entities (like PRs, etc.).

Before the launch one should create a [GitHub token](https://github.com/settings/tokens) and add it to the macOS Keychain as `GitHub API token for notifications`:

![GH-API-token-in-the-Keychain](https://user-images.githubusercontent.com/211000/148858206-0b571be7-5665-4870-a8f6-26a2a371583a.png)

On the badge click, the app opens your favourite browser to show pending notifications on [GitHub](https://github.com/notifications?query=reason%3Aparticipating+is%3Aunread).

Since this is a perfect application it does not give you a way to quit it. If you really want to stop it, you should show no mercy and kill it, for example with `pkill -f gh-notifications-osx.app`.

Good luck!

# How to build?

Use Xcode, and run `Product->Run` to execute, or `Product->Archive` to create a "release" version of the app.

You can use `Window->Organizer->Archives` to view all available archives.

To export an archive as a local app chose `Distribute App->Copy App`.
