import Flutter
import UIKit
import UserNotifications

/// Mirrors AlarmEvent in lib/features/alarm/alarm_event.dart, plus the ids of
/// the system alarms (or notifications) scheduled for it.
struct StoredAlarm: Codable {
  var id: Int
  var action: String
  var atMillis: Int64
  var reminderIntervalMin: Int
  var ringDurationSec: Int
  var maxReminders: Int
  var snoozePresets: [Int]
  var vibrate: Bool
  var isTest: Bool
  var dryRun: Bool
  /// The alarm itself followed by its pre-scheduled reminders.
  var chain: [String] = []

  var label: String { action == "clockIn" ? "Clock in" : "Clock out" }
  var title: String { isTest ? "Test: \(label)" : "Time to \(label.lowercased())" }
  var date: Date { Date(timeIntervalSince1970: TimeInterval(atMillis) / 1000) }

  /// iOS can't run code when an alarm goes unanswered, so reminders are
  /// scheduled up front. Capped to stay under the system's alarm limit.
  var ringDates: [Date] {
    let reminders = maxReminders < 0 ? 3 : min(maxReminders, 3)
    return (0...reminders).map { date.addingTimeInterval(TimeInterval($0 * reminderIntervalMin * 60)) }
  }

  func sameSchedule(_ other: StoredAlarm) -> Bool {
    var a = self, b = other
    a.chain = []
    b.chain = []
    return a.flutterMap as NSDictionary == b.flutterMap as NSDictionary
  }

  init(map: [String: Any]) {
    id = (map["id"] as! NSNumber).intValue
    action = map["action"] as! String
    atMillis = (map["atMillis"] as! NSNumber).int64Value
    reminderIntervalMin = (map["reminderIntervalMin"] as! NSNumber).intValue
    ringDurationSec = (map["ringDurationSec"] as! NSNumber).intValue
    maxReminders = (map["maxReminders"] as! NSNumber).intValue
    snoozePresets = (map["snoozePresets"] as! [NSNumber]).map(\.intValue)
    vibrate = map["vibrate"] as! Bool
    isTest = map["isTest"] as! Bool
    dryRun = map["dryRun"] as! Bool
  }

  var flutterMap: [String: Any] {
    [
      "id": id, "action": action, "atMillis": atMillis,
      "reminderIntervalMin": reminderIntervalMin, "ringDurationSec": ringDurationSec,
      "maxReminders": maxReminders, "snoozePresets": snoozePresets, "vibrate": vibrate,
      "isTest": isTest, "dryRun": dryRun,
    ]
  }
}

/// Persists scheduled alarms; intents run without Flutter, so state can't
/// live in Dart.
enum AlarmStore {
  private static let key = "clockmate.alarms"
  private static let launchKey = "clockmate.launchAlarmId"
  static let testId = 9

  static func all() -> [StoredAlarm] {
    guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
    return (try? JSONDecoder().decode([StoredAlarm].self, from: data)) ?? []
  }

  static func saveAll(_ alarms: [StoredAlarm]) {
    UserDefaults.standard.set(try? JSONEncoder().encode(alarms), forKey: key)
  }

  static func get(_ id: Int) -> StoredAlarm? { all().first { $0.id == id } }

  static func put(_ alarm: StoredAlarm) { saveAll(all().filter { $0.id != alarm.id } + [alarm]) }

  static func remove(_ id: Int) { saveAll(all().filter { $0.id != id }) }

  /// Alarm the user approved from the system UI; Flutter shows it when it opens.
  static var launchAlarmId: Int? {
    get { UserDefaults.standard.object(forKey: launchKey) as? Int }
    set { UserDefaults.standard.set(newValue, forKey: launchKey) }
  }
}

/// AlarmKit on iOS 26+, time-sensitive notifications before that.
enum AlarmBackend {
  static func schedule(_ alarm: StoredAlarm) async -> [String] {
    if #available(iOS 26.0, *) {
      return await AlarmKitBackend.schedule(alarm)
    }
    return await NotificationBackend.schedule(alarm)
  }

  static func cancel(_ chain: [String]) {
    if #available(iOS 26.0, *) {
      AlarmKitBackend.cancel(chain)
    } else {
      NotificationBackend.cancel(chain)
    }
  }

  static func stopAlerting(_ chain: [String]) {
    if #available(iOS 26.0, *) {
      AlarmKitBackend.stopAlerting(chain)
    } else {
      UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: chain)
    }
  }
}

/// Snooze, dismiss and planning logic shared by the Flutter channel and the
/// alarm intents.
enum AlarmEngine {
  static func scheduleAll(_ planned: [StoredAlarm]) async {
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let existing = AlarmStore.all()
    // Already ringing or reminding, or the test alarm: leave alone.
    let kept = existing.filter { $0.isTest || $0.atMillis <= now }
    let keptIds = Set(kept.map(\.id))
    var result = kept
    for var alarm in planned where !keptIds.contains(alarm.id) {
      if let old = existing.first(where: { $0.id == alarm.id }), old.sameSchedule(alarm) {
        alarm.chain = old.chain
      } else {
        if let old = existing.first(where: { $0.id == alarm.id }) { AlarmBackend.cancel(old.chain) }
        alarm.chain = await AlarmBackend.schedule(alarm)
      }
      result.append(alarm)
    }
    let resultIds = Set(result.map(\.id))
    for old in existing where !resultIds.contains(old.id) {
      AlarmBackend.cancel(old.chain)
    }
    AlarmStore.saveAll(result)
  }

  static func scheduleTest(_ alarm: StoredAlarm) async {
    remove(AlarmStore.testId)
    var alarm = alarm
    alarm.chain = await AlarmBackend.schedule(alarm)
    AlarmStore.put(alarm)
  }

  static func snooze(_ id: Int, minutes: Int) async {
    guard var alarm = AlarmStore.get(id) else { return }
    AlarmBackend.cancel(alarm.chain)
    alarm.atMillis = Int64((Date().timeIntervalSince1970 + TimeInterval(minutes * 60)) * 1000)
    alarm.chain = await AlarmBackend.schedule(alarm)
    AlarmStore.put(alarm)
  }

  /// Silences the alarm; its later reminders stay scheduled until complete().
  static func stopRinging(_ id: Int) {
    guard let alarm = AlarmStore.get(id) else { return }
    AlarmBackend.stopAlerting(alarm.chain)
  }

  static func remove(_ id: Int) {
    guard let alarm = AlarmStore.get(id) else { return }
    AlarmBackend.cancel(alarm.chain)
    AlarmStore.remove(id)
  }

  /// "Clock in/out" pressed on the system alarm.
  static func approved(_ id: Int) {
    stopRinging(id)
    AlarmStore.launchAlarmId = id
    if let alarm = AlarmStore.get(id) { AlarmBridge.shared?.notifyRing(alarm) }
  }

  /// "Later" pressed on the system alarm.
  static func later(_ id: Int) async {
    guard let alarm = AlarmStore.get(id) else { return }
    await snooze(id, minutes: alarm.reminderIntervalMin)
    AlarmBridge.shared?.notifyAction(id, "snoozed")
  }
}

/// Flutter side of the 'clockmate/alarm' channel.
final class AlarmBridge: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
  static var shared: AlarmBridge?
  private let channel: FlutterMethodChannel

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "clockmate/alarm", binaryMessenger: registrar.messenger())
    let instance = AlarmBridge(channel: channel)
    shared = instance
    registrar.addMethodCallDelegate(instance, channel: channel)
    UNUserNotificationCenter.current().delegate = instance
    NotificationBackend.registerCategories()
  }

  func notifyRing(_ alarm: StoredAlarm) {
    DispatchQueue.main.async { self.channel.invokeMethod("onRing", arguments: alarm.flutterMap) }
  }

  func notifyAction(_ id: Int, _ action: String) {
    DispatchQueue.main.async {
      self.channel.invokeMethod("onAction", arguments: ["id": id, "action": action])
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let id = (args?["id"] as? NSNumber)?.intValue ?? -1
    Task {
      var value: Any? = nil
      switch call.method {
      case "scheduleAll":
        let maps = call.arguments as? [[String: Any]] ?? []
        await AlarmEngine.scheduleAll(maps.map(StoredAlarm.init(map:)))
      case "scheduleTest":
        await AlarmEngine.scheduleTest(StoredAlarm(map: args ?? [:]))
      case "stopRinging":
        AlarmEngine.stopRinging(id)
      case "snooze":
        await AlarmEngine.snooze(id, minutes: (args?["minutes"] as? NSNumber)?.intValue ?? 10)
      case "dismiss", "complete":
        AlarmEngine.remove(id)
      case "releaseLockScreen":
        break
      case "takeLaunchEvent":
        if let launched = AlarmStore.launchAlarmId {
          AlarmStore.launchAlarmId = nil
          value = AlarmStore.get(launched)?.flutterMap
        }
      case "permissionStatus":
        value = await Permissions.status()
      case "requestPermission":
        await Permissions.request()
      default:
        value = FlutterMethodNotImplemented
      }
      let reply = value
      await MainActor.run { result(reply) }
    }
  }

  // MARK: Notification fallback (iOS < 26)

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if let id = notification.request.content.userInfo["alarmId"] as? Int, let alarm = AlarmStore.get(id) {
      notifyRing(alarm)
    }
    completionHandler([.banner, .sound, .list])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    guard let id = response.notification.request.content.userInfo["alarmId"] as? Int else {
      return completionHandler()
    }
    if response.actionIdentifier == NotificationBackend.laterAction {
      Task {
        await AlarmEngine.later(id)
        completionHandler()
      }
    } else {
      AlarmEngine.approved(id)
      completionHandler()
    }
  }
}

enum Permissions {
  static func status() async -> [String: Bool] {
    if #available(iOS 26.0, *) {
      return ["alarmKit": AlarmKitBackend.isAuthorized]
    }
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    return ["notifications": settings.authorizationStatus == .authorized]
  }

  /// Prompts once; after a denial only Settings can change it.
  static func request() async {
    let granted: Bool
    if #available(iOS 26.0, *) {
      granted = await AlarmKitBackend.requestAuthorization()
    } else {
      granted = (try? await UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    if !granted, let url = URL(string: UIApplication.openSettingsURLString) {
      await MainActor.run { UIApplication.shared.open(url) }
    }
  }
}

enum NotificationBackend {
  static let category = "CLOCKMATE_ALARM"
  static let approveAction = "approve"
  static let laterAction = "later"

  static func registerCategories() {
    let approve = UNNotificationAction(identifier: approveAction, title: "Open to approve", options: [.foreground])
    let later = UNNotificationAction(identifier: laterAction, title: "Later", options: [])
    UNUserNotificationCenter.current().setNotificationCategories([
      UNNotificationCategory(identifier: category, actions: [approve, later], intentIdentifiers: []),
    ])
  }

  static func schedule(_ alarm: StoredAlarm) async -> [String] {
    var ids: [String] = []
    for (index, date) in alarm.ringDates.enumerated() {
      let content = UNMutableNotificationContent()
      content.title = index == 0 ? alarm.title : "Reminder: \(alarm.title)"
      content.body = "Open ClockMate to approve, or choose Later."
      content.sound = .default
      content.categoryIdentifier = category
      content.interruptionLevel = .timeSensitive
      content.userInfo = ["alarmId": alarm.id]
      let interval = max(1, date.timeIntervalSinceNow)
      let id = "clockmate.\(alarm.id).\(index).\(alarm.atMillis)"
      let request = UNNotificationRequest(
        identifier: id,
        content: content,
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
      )
      if (try? await UNUserNotificationCenter.current().add(request)) != nil { ids.append(id) }
    }
    return ids
  }

  static func cancel(_ ids: [String]) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: ids)
    center.removeDeliveredNotifications(withIdentifiers: ids)
  }
}
