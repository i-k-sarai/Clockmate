package com.karasingh.clockmate

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.util.Date

/**
 * Native alarm screen. It is the full-screen intent target and is launched
 * straight from RingService when the app may draw over other apps, so it
 * shows over the lock screen and the home screen without booting Flutter.
 *
 * Snooze and Dismiss work without unlocking. Clock in asks to unlock, then
 * hands over to the Flutter app, which punches right away.
 */
class AlarmActivity : Activity() {
    companion object {
        /** The visible alarm screen, if any. Same process, so a direct reference is fine. */
        private var current: AlarmActivity? = null

        fun launchIntent(context: Context, alarmId: Int): Intent =
            Intent(context, AlarmActivity::class.java)
                .putExtra(EXTRA_ALARM_ID, alarmId)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_NO_USER_ACTION or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )

        /** The alarm stopped ringing (answered elsewhere, snoozed or timed out). */
        fun close(alarmId: Int) {
            current?.takeIf { it.alarmId == alarmId }?.finish()
        }

        // Matches the Flutter ring screen (lib/app/theme.dart).
        private const val BG_TOP = 0xFF1E1B4B.toInt()
        private const val BG_BOTTOM = 0xFF0F172A.toInt()
        private const val ACCENT = 0xFF14B8A6.toInt()
        private const val MUTED = 0xB3FFFFFF.toInt()
        private const val CHIP = 0x1FFFFFFF
    }

    private var alarmId = -1
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var clock: TextView
    private val tick = object : Runnable {
        override fun run() {
            clock.text = android.text.format.DateFormat.getTimeFormat(this@AlarmActivity).format(Date())
            handler.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.statusBarColor = BG_TOP
        window.navigationBarColor = BG_BOTTOM
        bind(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        bind(intent)
    }

    override fun onResume() {
        super.onResume()
        current = this
        handler.post(tick)
    }

    override fun onPause() {
        handler.removeCallbacks(tick)
        super.onPause()
    }

    override fun onDestroy() {
        if (current === this) current = null
        super.onDestroy()
    }

    @Deprecated("Back must not silently drop a ringing alarm.")
    override fun onBackPressed() {
        // Leaving has to be an explicit choice: approve, snooze or dismiss.
    }

    private fun bind(intent: Intent?) {
        val id = intent?.getIntExtra(EXTRA_ALARM_ID, -1) ?: -1
        val event = AlarmStore(this).get(id)
        if (event == null) {
            finish()
            return
        }
        alarmId = id
        setContentView(build(event))
        current = this
    }

    private fun build(event: AlarmEvent): View {
        val verb = if (event.action == "clockIn") "clock in" else "clock out"
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(BG_TOP, BG_BOTTOM))
            setPadding(dp(24), dp(48), dp(24), dp(32))
        }

        if (event.isTest) {
            root.addView(label(if (event.dryRun) "TEST · DRY RUN" else "TEST · LIVE", 12f, MUTED, bold = true))
        }
        root.addView(spacer(1f))
        root.addView(halo())
        root.addView(gap(24))
        clock = label("", 64f, Color.WHITE, bold = true).apply { letterSpacing = -0.03f }
        root.addView(clock)
        root.addView(gap(4))
        root.addView(label("Time to $verb", 24f, Color.WHITE, bold = true))
        root.addView(gap(6))
        root.addView(label("Scheduled for ${event.timeLabel(this)}", 15f, MUTED))
        root.addView(spacer(1f))

        root.addView(
            pill(if (event.action == "clockIn") "Clock in" else "Clock out", ACCENT, Color.WHITE, dp(64)) {
                approve()
            },
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(64)),
        )
        root.addView(gap(20))
        root.addView(label("Snooze", 13f, MUTED, bold = true))
        root.addView(gap(10))
        val chips = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        event.snoozePresets.take(4).forEach { minutes ->
            chips.addView(
                pill("$minutes min", CHIP, Color.WHITE, dp(44)) {
                    AlarmEngine.snooze(this, event.id, minutes, fromNotification = true)
                    finish()
                },
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(44)).apply {
                    marginStart = dp(4)
                    marginEnd = dp(4)
                },
            )
        }
        root.addView(chips)
        root.addView(gap(12))
        root.addView(
            Button(this).apply {
                text = "Dismiss for today"
                isAllCaps = false
                setTextColor(MUTED)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                background = null
                setOnClickListener {
                    AlarmEngine.dismiss(this@AlarmActivity, event.id, fromNotification = true)
                    finish()
                }
            },
        )
        return root
    }

    /** Unlock, then open the app to punch. The alarm stays up if unlocking is cancelled. */
    private fun approve() {
        val id = alarmId
        val openApp = {
            startActivity(MainActivity.alarmIntent(this, id, approve = true))
            finish()
        }
        val keyguard = getSystemService(KeyguardManager::class.java)
        if (!keyguard.isKeyguardLocked) return openApp()
        keyguard.requestDismissKeyguard(
            this,
            object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() = openApp()
            },
        )
    }

    private fun halo(): View {
        val size = dp(112)
        return ImageView(this).apply {
            layoutParams = LinearLayout.LayoutParams(size, size)
            setImageResource(R.drawable.ic_stat_alarm)
            setColorFilter(ACCENT)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            setPadding(dp(30), dp(30), dp(30), dp(30))
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0x3314B8A6)
                setStroke(dp(2), 0x6614B8A6)
            }
            animate().scaleX(1.08f).scaleY(1.08f).setDuration(900).withEndAction(object : Runnable {
                var grow = false
                override fun run() {
                    val s = if (grow) 1.08f else 1f
                    grow = !grow
                    animate().scaleX(s).scaleY(s).setDuration(900).withEndAction(this)
                }
            })
        }
    }

    private fun label(value: String, sp: Float, color: Int, bold: Boolean = false) = TextView(this).apply {
        text = value
        gravity = Gravity.CENTER
        setTextColor(color)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sp)
        if (bold) typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }

    private fun pill(label: String, bg: Int, fg: Int, height: Int, onClick: () -> Unit) = Button(this).apply {
        text = label
        isAllCaps = false
        setTextColor(fg)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        stateListAnimator = null
        minHeight = height
        setPadding(dp(20), 0, dp(20), 0)
        background = GradientDrawable().apply {
            cornerRadius = height / 2f
            setColor(bg)
        }
        setOnClickListener { onClick() }
    }

    private fun gap(heightDp: Int) = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(1, dp(heightDp))
    }

    private fun spacer(weight: Float) = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(1, 0, weight)
    }

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()
}
