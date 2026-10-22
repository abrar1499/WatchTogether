package com.abrar.watchtogether

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.MutableContextWrapper
import android.graphics.Color
import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONObject
import java.net.URLEncoder

/**
 * One YouTube search page that is created once and kept warm in the background,
 * so opening search feels instant instead of loading a website every time.
 */
@SuppressLint("StaticFieldLeak")
object SearchWeb {

    private var web: WebView? = null
    private var wrapper: MutableContextWrapper? = null
    private var picked = false
    private var lastQuery: String? = null

    var onPick: ((String) -> Unit)? = null
    var onProgress: ((Int) -> Unit)? = null

    /** Start loading YouTube in the background (call when the room opens). */
    fun warmUp(context: Context) {
        if (web != null) return
        val app = context.applicationContext
        val w = MutableContextWrapper(app)
        wrapper = w
        web = create(w).also { it.loadUrl(HOME) }
    }

    /** Take the warm WebView to show it inside the search sheet. */
    fun obtain(activity: Activity): WebView {
        warmUp(activity)
        wrapper?.baseContext = activity
        val v = web!!
        (v.parent as? ViewGroup)?.removeView(v)
        picked = false
        v.onResume()
        return v
    }

    /** The sheet closed: keep the page alive for next time, but quiet. */
    fun release() {
        val v = web ?: return
        (v.parent as? ViewGroup)?.removeView(v)
        stopMedia(v)
        wrapper?.baseContext = v.context.applicationContext
        onPick = null
        onProgress = null
    }

    fun search(query: String) {
        val q = query.trim()
        if (q.isEmpty()) return
        val v = web ?: return
        if (q == lastQuery && v.url?.contains("/results") == true) return   // already showing it
        lastQuery = q
        v.loadUrl(RESULTS + URLEncoder.encode(q, "UTF-8"))
    }

    fun destroy() {
        web?.let {
            (it.parent as? ViewGroup)?.removeView(it)
            it.stopLoading()
            it.destroy()
        }
        web = null
        wrapper = null
        lastQuery = null
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun create(context: Context): WebView {
        val v = WebView(context)
        with(v.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            cacheMode = WebSettings.LOAD_DEFAULT
            mediaPlaybackRequiresUserGesture = true
            offscreenPreRaster = true   // smoother scrolling
        }
        v.setBackgroundColor(Color.parseColor("#141416"))
        v.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, newProgress: Int) {
                onProgress?.invoke(newProgress)
            }
        }
        v.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (tryPick(view, request.url.toString(), fromHistory = false)) return true
                // Block "open in YouTube app" style links (intent://, vnd.youtube://)
                val scheme = request.url.scheme ?: return true
                return scheme != "http" && scheme != "https"
            }

            // YouTube's mobile site changes pages without reloading, so watch the history too
            override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) {
                tryPick(view, url, fromHistory = true)
            }

            override fun onPageCommitVisible(view: WebView, url: String) = injectCss(view)
            override fun onPageFinished(view: WebView, url: String) = injectCss(view)
        }
        return v
    }

    private fun tryPick(view: WebView, url: String, fromHistory: Boolean): Boolean {
        val isVideoPage = url.contains("/watch") || url.contains("/shorts/")
        if (!isVideoPage) return false
        if (picked) return true
        val id = YouTubeLink.extractId(url) ?: return false
        picked = true
        // Don't let YouTube start that video in the background; go back to the results
        stopMedia(view)
        if (fromHistory) view.evaluateJavascript("history.back();", null)
        onPick?.invoke(id)
        return true
    }

    private fun stopMedia(view: WebView) {
        view.evaluateJavascript(
            "document.querySelectorAll('video,audio').forEach(function(m){try{m.pause();m.muted=true;}catch(e){}});",
            null
        )
    }

    // Hide YouTube's own top bar and bottom tabs; our search bar replaces them
    private fun injectCss(view: WebView) {
        val css = JSONObject.quote(RemoteConfig.searchCss ?: DEFAULT_CSS)
        view.evaluateJavascript(
            "(function(){if(document.getElementById('wtcss'))return;" +
                "var s=document.createElement('style');s.id='wtcss';s.textContent=" + css + ";" +
                "(document.head||document.documentElement).appendChild(s);})();",
            null
        )
    }

    private const val DEFAULT_CSS =
        "ytm-mobile-topbar-renderer,#header-bar,.mobile-topbar-header,ytm-pivot-bar-renderer," +
            "ytm-feed-filter-chip-bar-renderer{display:none!important}" +
            "body,ytm-app{padding-top:0!important;background:#141416!important}"

    private const val HOME = "https://m.youtube.com/"
    private const val RESULTS = "https://m.youtube.com/results?search_query="
}
