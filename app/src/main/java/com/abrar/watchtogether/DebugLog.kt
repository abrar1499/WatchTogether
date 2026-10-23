package com.abrar.watchtogether

import android.os.Handler
import android.os.Looper
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * What the app is doing, step by step (taps, links found, videos loaded, errors).
 * Shown in the room by long-pressing the room code, so a screenshot shows exactly what failed.
 */
object DebugLog {
    private const val MAX = 120
    private val lines = ArrayDeque<String>()
    private val fmt = SimpleDateFormat("HH:mm:ss", Locale.US)
    private val main = Handler(Looper.getMainLooper())

    /** Called on the main thread whenever a line is added. */
    var onChange: (() -> Unit)? = null

    @Synchronized
    fun log(tag: String, msg: String) {
        val line = fmt.format(Date()) + " " + tag + ": " + msg.take(300)
        lines.addLast(line)
        while (lines.size > MAX) lines.removeFirst()
        main.post { onChange?.invoke() }
    }

    @Synchronized
    fun text(): String = lines.joinToString("\n")

    @Synchronized
    fun clear() {
        lines.clear()
        main.post { onChange?.invoke() }
    }
}
