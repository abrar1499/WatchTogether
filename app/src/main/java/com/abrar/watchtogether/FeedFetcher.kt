package com.abrar.watchtogether

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import org.json.JSONArray

/**
 * After a TikTok video is shared, quietly opens the creator's page in a hidden view and
 * collects their videos, so the room can keep swiping like a feed.
 */
object FeedFetcher {

    private val main = Handler(Looper.getMainLooper())
    private var web: WebView? = null

    private val USER = Regex("tiktok\\.com/(@[^/?#]+)")

    fun creatorPage(url: String): String? =
        USER.find(url)?.let { "https://www.tiktok.com/" + it.groupValues[1] }

    @SuppressLint("SetJavaScriptEnabled")
    fun fetch(host: ViewGroup, pageUrl: String, firstKey: String, onList: (List<String>) -> Unit) {
        stop()
        val v = WebView(host.context)
        web = v
        with(v.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = true
        }
        v.webViewClient = WebViewClient()
        v.alpha = 0f
        // Tiny and invisible, but attached so the page actually lays out and loads its list
        host.addView(v, 0, FrameLayout.LayoutParams(360, 640))
        v.loadUrl(pageUrl)

        var tries = 0
        val poll = object : Runnable {
            override fun run() {
                val w = web ?: return
                w.evaluateJavascript(COLLECT) { raw ->
                    val keys = parse(raw)
                    tries++
                    if (keys.size >= 8 || tries >= 15) {
                        val list = (listOf(firstKey) + keys).distinct()
                        stop()
                        if (list.size > 1) onList(list.take(60))
                    } else {
                        main.postDelayed(this, 1000)
                    }
                }
            }
        }
        main.postDelayed(poll, 1500)
    }

    fun stop() {
        web?.let {
            (it.parent as? ViewGroup)?.removeView(it)
            it.stopLoading()
            it.destroy()
        }
        web = null
    }

    private fun parse(raw: String?): List<String> = try {
        // evaluateJavascript returns the JSON string quoted
        val arr = JSONArray(JSONArray("[$raw]").getString(0))
        (0 until arr.length()).map { "tt:" + arr.getString(it) }.distinct()
    } catch (e: Exception) {
        emptyList()
    }

    private const val COLLECT =
        "(function(){document.querySelectorAll('video').forEach(function(m){m.muted=true;m.pause();});" +
            "var seen={},out=[],re=/\\/video\\/(\\d{17,20})/;" +
            "document.querySelectorAll('a[href*=\"/video/\"]').forEach(function(a){var m=re.exec(a.href);" +
            "if(m&&!seen[m[1]]){seen[m[1]]=1;out.push(m[1]);}});return JSON.stringify(out);})()"
}
