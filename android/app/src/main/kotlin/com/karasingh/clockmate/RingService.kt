package com.karasingh.clockmate

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings

/**
 * Foreground service that keeps one alarm ringing until it is answered or
 * times out. Its notification carries the alarm tone.
 */
class RingService : Service() {
    companion object {
        /** The running service, if any. Same process, so a direct reference is fine. */
        var instance: RingService? = null
            private set

        fun ring(context: Context, id: Int) {
            context.startForegroundService(
                Intent(context, RingService::class.java).putExtra(EXTRA_ALARM_ID, id),
            )
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var current: AlarmEvent? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val timeout = Runnable { current?.let { AlarmEngine.onMissed(this, it.id) } }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onDestroy() {
        stopAlerting()
        instance = null
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = intent?.getIntExtra(EXTRA_ALARM_ID, -1) ?: -1
        val store = AlarmStore(this)
        val event = store.get(id)
        if (event == null) {
            // startForegroundService requires startForeground even when bailing out.
            startInForeground(Notifications.placeholder(this))
            if (current == null) stopSelf()
            return START_NOT_STICKY
        }

        // A second alarm while one is ringing: the first becomes a reminder.
        // Clear `current` first so onMissed's silence() doesn't stop this service.
        current?.takeIf { it.id != id }?.let { previous ->
            current = null
            stopAlerting()
            AlarmEngine.onMissed(this, previous.id)
        }

        event.active = true
        store.put(event)
        current = event
        startInForeground(Notifications.ringing(this, event))
        showAlarmScreen(event.id)
        startAlerting(event)
        handler.postDelayed(timeout, event.ringDurationSec * 1000L)
        AlarmEngine.listener?.onRing(event)
        return START_NOT_STICKY
    }

    /**
     * The full-screen intent only covers a locked or sleeping screen, and some
     * phones block heads-up notifications for new apps. Apps allowed to draw
     * over other apps may start activities from the background, so open the
     * alarm screen directly: it then shows over the home screen too.
     */
    private fun showAlarmScreen(id: Int) {
        if (!Settings.canDrawOverlays(this) || MainActivity.visible) return
        try {
            startActivity(AlarmActivity.launchIntent(this, id))
        } catch (e: RuntimeException) {
            // Blocked by the system; the notification is still there.
        }
    }

    /** Stops ringing [id] if it is the alarm currently ringing. */
    fun silence(id: Int) {
        if (current?.id != id) return
        AlarmActivity.close(id)
        current = null
        stopAlerting()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun startInForeground(notification: android.app.Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                Notifications.RING_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED,
            )
        } else {
            startForeground(Notifications.RING_ID, notification)
        }
    }

    private fun startAlerting(event: AlarmEvent) {
        stopAlerting()
        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "clockmate:ring")
            .apply { acquire((event.ringDurationSec + 5) * 1000L) }
        // The tone comes from the insistent ring notification (see Notifications).

        if (event.vibrate) {
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                getSystemService(VibratorManager::class.java).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Vibrator::class.java)
            }
            vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 800, 600), 0))
        }
    }

    private fun stopAlerting() {
        handler.removeCallbacks(timeout)
        vibrator?.cancel()
        vibrator = null
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
    }
}
