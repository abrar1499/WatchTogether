package com.abrar.watchtogether

import android.content.Context
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Look-and-feel settings that can change without a new app build.
 *
 * The app always starts instantly from the copy saved on the phone; a fresh copy
 * (a few KB from GitHub) is fetched quietly in the background and used from then on.
 * If anything is missing or broken, the built-in defaults are used.
 */
object RemoteConfig {

    private const val CONFIG_URL =
        "https://raw.githubusercontent.com/abrar1499/WatchTogether/main/remote/config.json"
    private const val PREFS = "remote_config"
    private const val KEY = "json"

    /** CSS for the video page (hides YouTube's UI, video size, reflection, blur). */
    @Volatile var playerCss: String? = null
        private set

    /** CSS for the YouTube search sheet. */
    @Volatile var searchCss: String? = null
        private set

    /** Replacement app text, by string name (see Texts.kt). */
    @Volatile var texts: Map<String, String> = emptyMap()
        private set

    /** Search sheet height as a fraction of the screen (the rest shows the video). */
    @Volatile var sheetHeight: Float = 0.62f
        private set

    /** Opacity of chat messages, newest first. */
    @Volatile var chatLevels: FloatArray? = null
        private set

    fun init(context: Context) {
        val sp = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        sp.getString(KEY, null)?.let { apply(it) }

        thread {
            try {
                val conn = URL(CONFIG_URL).openConnection() as HttpURLConnection
                conn.connectTimeout = 6_000
                conn.readTimeout = 6_000
                conn.useCaches = false
                if (conn.responseCode == 200) {
                    val text = conn.inputStream.bufferedReader().readText()
                    if (apply(text)) sp.edit().putString(KEY, text).apply()
                }
                conn.disconnect()
            } catch (e: Exception) {
                // Offline or GitHub unreachable: keep using the saved copy / defaults
            }
        }
    }

    /** Returns true if the text was valid and applied. */
    private fun apply(text: String): Boolean = try {
        val json = JSONObject(text)
        // Only settings meant for this app version or older are used
        if (json.optInt("minAppVersion", 0) > BuildConfig.VERSION_CODE) {
            false
        } else {
            playerCss = json.optString("playerCss").takeIf { it.isNotBlank() }
            searchCss = json.optString("searchCss").takeIf { it.isNotBlank() }
            chatLevels = json.optJSONArray("chatLevels")?.let { arr ->
                FloatArray(arr.length()) { i -> arr.optDouble(i, 0.0).toFloat().coerceIn(0f, 1f) }
            }?.takeIf { it.isNotEmpty() }
            sheetHeight = json.optDouble("sheetHeight", 0.62).toFloat().coerceIn(0.4f, 0.95f)
            texts = json.optJSONObject("texts")?.let { obj ->
                obj.keys().asSequence().associateWith { obj.optString(it) }.filterValues { it.isNotEmpty() }
            } ?: emptyMap()
            true
        }
    } catch (e: Exception) {
        false
    }
}
