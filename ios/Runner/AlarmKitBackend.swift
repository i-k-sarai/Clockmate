import AlarmKit
import AppIntents
import SwiftUI

@available(iOS 26.0, *)
struct ClockMateAlarmMetadata: AlarmMetadata {
  var alarmId: Int
}

/// Rings like the Clock app: on the lock screen, through silent mode and Focus.
@available(iOS 26.0, *)
enum AlarmKitBackend {
  private static let tint = Color(red: 0.06, green: 0.46, blue: 0.43)

  static var isAuthorized: Bool { AlarmManager.shared.authorizationState == .authorized }

  static func requestAuthorization() async -> Bool {
    (try? await AlarmManager.shared.requestAuthorization()) == .authorized
  }

  static func schedule(_ alarm: StoredAlarm) async -> [String] {
    if AlarmManager.shared.authorizationState == .notDetermined {
      _ = await requestAuthorization()
    }
    let alert = AlarmPresentation.Alert(
      title: LocalizedStringResource(stringLiteral: alarm.title),
      stopButton: AlarmButton(text: "Later", textColor: .white, systemImageName: "zzz"),
      secondaryButton: AlarmButton(
        text: LocalizedStringResource(stringLiteral: alarm.label),
        textColor: .white,
        systemImageName: "checkmark.circle.fill"
      ),
      secondaryButtonBehavior: .custom
    )
    let attributes = AlarmAttributes(
      presentation: AlarmPresentation(alert: alert),
      metadata: ClockMateAlarmMetadata(alarmId: alarm.id),
      tintColor: tint
    )

    var ids: [String] = []
    for date in alarm.ringDates where date > Date() || ids.isEmpty {
      let id = UUID()
      let configuration = AlarmManager.AlarmConfiguration.alarm(
        schedule: .fixed(max(date, Date().addingTimeInterval(2))),
        attributes: attributes,
        stopIntent: LaterIntent(alarmId: alarm.id),
        secondaryIntent: ApproveIntent(alarmId: alarm.id)
      )
      do {
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        ids.append(id.uuidString)
      } catch {
        // Not authorized, or the system limit on alarms was reached.
        break
      }
    }
    return ids
  }

  static func cancel(_ chain: [String]) {
    for id in chain.compactMap(UUID.init(uuidString:)) {
      try? AlarmManager.shared.cancel(id: id)
    }
  }

  static func stopAlerting(_ chain: [String]) {
    let alarms = (try? AlarmManager.shared.alarms) ?? []
    let alerting = Set(alarms.filter { $0.state == .alerting }.map(\.id))
    for id in chain.compactMap(UUID.init(uuidString:)) where alerting.contains(id) {
      try? AlarmManager.shared.stop(id: id)
    }
  }
}

/// The "Clock in/out" button on the system alarm. Opens ClockMate, which
/// shows the slide-to-approve screen.
@available(iOS 26.0, *)
struct ApproveIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Approve ClockMate alarm"
  static let supportedModes: IntentModes = .foreground(.immediate)

  @Parameter(title: "Alarm")
  var alarmId: Int

  init() {}

  init(alarmId: Int) {
    self.alarmId = alarmId
  }

  func perform() async throws -> some IntentResult {
    AlarmEngine.approved(alarmId)
    return .result()
  }
}

/// The "Later" (stop) button: ring again after the reminder interval.
@available(iOS 26.0, *)
struct LaterIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Remind me later"
  static let supportedModes: IntentModes = .background

  @Parameter(title: "Alarm")
  var alarmId: Int

  init() {}

  init(alarmId: Int) {
    self.alarmId = alarmId
  }

  func perform() async throws -> some IntentResult {
    await AlarmEngine.later(alarmId)
    return .result()
  }
}
