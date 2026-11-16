# iOS widget: one-time Xcode setup

The widget's source lives in `ios/ClockMateWidget/` and the app already
pushes its data (via `home_widget` and the App Group
`group.com.karasingh.clockmate`). What file edits cannot do is create the
extension *target* — that part must be done once in Xcode:

1. **Create the target.** Open `ios/Runner.xcworkspace` in Xcode →
   File → New → Target… → **Widget Extension**.
   - Product name: `ClockMateWidget` (exactly — the app calls
     `updateWidget(iOSName: 'ClockMateWidget')`).
   - Uncheck "Include Configuration App Intent" / Live Activity options.
   - Don't activate the scheme prompt matters either way.
   - Set the extension's **minimum deployment target to iOS 15.0** (General
     tab of the new target) so it matches the app.

2. **Replace the template files.** Delete the Swift files Xcode generated
   inside its new `ClockMateWidget` group, then add the existing files from
   `ios/ClockMateWidget/` to that target instead:
   - `ClockMateWidget.swift`, `ClockMateWidgetBundle.swift`
   - set the target's Info.plist to `ios/ClockMateWidget/Info.plist`
     (Build Settings → `INFOPLIST_FILE`), or merge its `NSExtension` block.

3. **App Group (needs a paid Apple developer team).**
   - In the Apple Developer portal (or via Xcode's automatic signing), make
     sure the App Group `group.com.karasingh.clockmate` exists.
   - Runner target → Signing & Capabilities → + Capability → **App Groups**
     → tick `group.com.karasingh.clockmate`. Xcode will use
     `ios/Runner/Runner.entitlements` (already in the repo); if it creates a
     new file, point `CODE_SIGN_ENTITLEMENTS` at the existing one.
   - Repeat for the ClockMateWidget target with
     `ios/ClockMateWidget/ClockMateWidget.entitlements`.

4. **Bundle id.** The extension's bundle identifier must be
   `com.karasingh.clockmate.ClockMateWidget` (Xcode derives this
   automatically from the app id).

5. Build & run the Runner scheme on a device, then add the ClockMate widget
   from the home screen. It fills in after the app has fetched a status once.

Without a paid team / App Group, the widget cannot share data with the app —
ship Android-only in that case.
