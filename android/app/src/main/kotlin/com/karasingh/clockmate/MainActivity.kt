package com.karasingh.clockmate

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), AlarmEngine.Listener {
    companion object {
        /** The app is in the foreground; it shows its own ring screen then. */
        var visible = false
            private set

        fun alarmIntent(context: Context, alarmId: Int, approve: Boolean = false): Intent =
            Intent(context, MainActivity::class.java)
                .putExtra(EXTRA_ALARM_ID, alarmId)
                .putExtra(EXTRA_APPROVE, approve)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    }

    private var channel: MethodChannel? = null

    /** Alarm the app was cold-started from; Dart picks it up once ready. */
    private var launchAlarmId: Int? = null

    /** The user already chose to approve on the native alarm screen. */
    private var launchApprove = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "clockmate/alarm")
            .apply { setMethodCallHandler(::onMethodCall) }
        AlarmEngine.listener = this
        Notifications.ensureChannels(this)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleAlarmIntent(intent, coldStart = true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAlarmIntent(intent, coldStart = false)
    }

    override fun onResume() {
        super.onResume()
        visible = true
    }

    override fun onPause() {
        visible = false
        super.onPause()
    }

    override fun onDestroy() {
        if (AlarmEngine.listener === this) AlarmEngine.listener = null
        super.onDestroy()
    }

    private fun handleAlarmIntent(intent: Intent?, coldStart: Boolean) {
        val id = intent?.getIntExtra(EXTRA_ALARM_ID, -1) ?: -1
        if (id < 0) return
        val approve = intent?.getBooleanExtra(EXTRA_APPROVE, false) ?: false
        intent?.removeExtra(EXTRA_ALARM_ID)
        intent?.removeExtra(EXTRA_APPROVE)
        // The native alarm screen covers the lock screen; once the user chose to
        // approve, the device is unlocked, so the app itself needn't show over it.
        showOverLockScreen(!approve)
        AlarmActivity.close(id)
        if (coldStart) {
            launchAlarmId = id
            launchApprove = approve
        } else {
            AlarmStore(this).get(id)?.let { sendRing(it, approve) }
        }
    }

    /** Only while an alarm is on screen; normal launches stay behind the lock screen. */
    private fun showOverLockScreen(show: Boolean) {
        setShowWhenLocked(show)
        setTurnScreenOn(show)
    }

    override fun onRing(event: AlarmEvent) = sendRing(event, approve = false)

    private fun sendRing(event: AlarmEvent, approve: Boolean) {
        channel?.invokeMethod("onRing", event.toFlutterMap() + ("approve" to approve))
    }

    override fun onAction(id: Int, action: String) {
        channel?.invokeMethod("onAction", mapOf("id" to id, "action" to action))
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // Not call.argument(): scheduleAll sends a list, which it can't read.
        val id = ((call.arguments as? Map<*, *>)?.get("id") as? Number)?.toInt()
        when (call.method) {
            "scheduleAll" -> {
                val events = (call.arguments as List<*>).map { AlarmEvent.fromFlutterMap(it as Map<*, *>) }
                AlarmEngine.scheduleAll(this, events)
            }
            "scheduleTest" -> AlarmEngine.scheduleTest(this, AlarmEvent.fromFlutterMap(call.arguments as Map<*, *>))
            "stopRinging" -> AlarmEngine.stopRinging(this, id!!)
            "snooze" -> AlarmEngine.snooze(this, id!!, call.argument<Number>("minutes")!!.toInt(), fromNotification = false)
            "dismiss" -> AlarmEngine.dismiss(this, id!!, fromNotification = false)
            "complete" -> AlarmEngine.complete(this, id!!)
            "syncSession" -> {
                val args = call.arguments as Map<*, *>
                KekaStateStore(this).saveSession(
                    host = args["host"] as? String,
                    token = args["token"] as? String,
                    expiresAtMillis = (args["expiresAtMillis"] as? Number)?.toLong(),
                )
            }
            "syncStatus" -> {
                val args = call.arguments as Map<*, *>
                KekaStateStore(this).saveStatus(
                    KekaStateStore.Status(
                        clockedIn = args["clockedIn"] as? Boolean ?: false,
                        sinceMillis = (args["sinceMillis"] as? Number)?.toLong() ?: 0L,
                        lastClockOutMillis = (args["lastClockOutMillis"] as? Number)?.toLong() ?: 0L,
                        fetchedAtMillis = (args["fetchedAtMillis"] as? Number)?.toLong() ?: 0L,
                    ),
                )
            }
            "releaseLockScreen" -> showOverLockScreen(false)
            "takeLaunchEvent" -> {
                val launched = launchAlarmId?.let { AlarmStore(this).get(it) }
                val approve = launchApprove
                launchAlarmId = null
                launchApprove = false
                return result.success(launched?.toFlutterMap()?.plus("approve" to approve))
            }
            "permissionStatus" -> return result.success(permissionStatus())
            "requestPermission" -> requestPermission(call.argument<String>("kind")!!)
            else -> return result.notImplemented()
        }
        result.success(null)
    }

    private fun permissionStatus(): Map<String, Boolean> {
        val notifications = getSystemService(NotificationManager::class.java)
        return linkedMapOf(
            "notifications" to notifications.areNotificationsEnabled(),
            "exactAlarm" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                getSystemService(AlarmManager::class.java).canScheduleExactAlarms()),
            "fullScreen" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
                notifications.canUseFullScreenIntent()),
            "alarmChannel" to Notifications.alarmChannelHealthy(this),
            "overlay" to Settings.canDrawOverlays(this),
            "batteryOptimization" to
                getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName),
        )
    }

    private fun requestPermission(kind: String) {
        val packageUri = Uri.parse("package:$packageName")
        val intent = when (kind) {
            "notifications" -> {
                val prefs = getSharedPreferences("clockmate_permissions", MODE_PRIVATE)
                val canPrompt = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
                    !prefs.getBoolean("askedNotifications", false)
                if (canPrompt) {
                    // The system dialog only shows once; later taps open settings instead.
                    prefs.edit().putBoolean("askedNotifications", true).apply()
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                    return
                }
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
            "exactAlarm" -> Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, packageUri)
            "fullScreen" -> Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, packageUri)
            "alarmChannel" -> Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                .putExtra(Settings.EXTRA_CHANNEL_ID, Notifications.ALARM_CHANNEL)
            "overlay" -> Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, packageUri)
            "batteryOptimization" -> Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, packageUri)
            else -> return
        }
        startActivity(intent)
    }
}
