package com.abrar.watchtogether

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.MutableContextWrapper
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
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

    /** The site currently open in the search sheet. */
    var site = Site.YOUTUBE
        private set

    /** Each site's own icon, fetched from the site (like a browser tab icon). */
    val icons = HashMap<Site, android.graphics.Bitmap>()

    var onPick: ((String) -> Unit)? = null
    var onProgress: ((Int) -> Unit)? = null
    var onLoadingStart: (() -> Unit)? = null
    var onContentReady: (() -> Unit)? = null

    /** True once real results (video cards) are on the page. */
    var contentReady = false
        private set

    private val main = Handler(Looper.getMainLooper())
    private var pollStarted = 0L
    private val poll = object : Runnable {
        override fun run() {
            val v = web ?: return
            val check = if (site == Site.YOUTUBE) READY_CHECK else "document.readyState=='complete'"
            v.evaluateJavascript(check) { result ->
                if (result == "true" || SystemClock.elapsedRealtime() - pollStarted > 8_000) markReady()
                else main.postDelayed(this, 120)
            }
        }
    }

    private fun startPolling() {
        contentReady = false
        pollStarted = SystemClock.elapsedRealtime()
        main.removeCallbacks(poll)
        main.postDelayed(poll, 120)
    }

    private fun markReady() {
        main.removeCallbacks(poll)
        if (contentReady) return
        contentReady = true
        onContentReady?.invoke()
    }

    /** Start loading YouTube in the background (call when the room opens). */
    fun warmUp(context: Context) {
        if (web != null) return
        val app = context.applicationContext
        val w = MutableContextWrapper(app)
        wrapper = w
        web = create(w).also { it.loadUrl(site.home) }
        startPolling()
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
        onLoadingStart = null
        onContentReady = null
    }

    fun search(query: String) {
        val q = query.trim()
        if (q.isEmpty()) return
        val v = web ?: return
        if (q == lastQuery && v.url?.contains("/results") == true) return   // already showing it
        lastQuery = q
        onLoadingStart?.invoke()
        v.loadUrl(site.searchUrl + URLEncoder.encode(q, "UTF-8"))
        startPolling()
    }

    /** Open another site's tab. */
    fun switchTo(newSite: Site) {
        if (newSite == site && web != null) return
        site = newSite
        lastQuery = null
        val v = web ?: return
        stopMedia(v)
        onLoadingStart?.invoke()
        v.loadUrl(site.home)
        startPolling()
    }

    fun destroy() {
        main.removeCallbacks(poll)
        contentReady = false
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
        if (site != Site.YOUTUBE) return false   // other sites can be browsed, not played yet
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
        if (site != Site.YOUTUBE) return
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
            "body,ytm-app{padding-top:0!important;background:#141416!important}" +
            "ytm-spinner,ytm-spinner-renderer,.spinner-container{opacity:0!important}" +
            "ytm-video-with-context-renderer .media-item-thumbnail-container," +
            "ytm-media-item .media-item-thumbnail-container," +
            "ytm-video-with-context-renderer>a:first-child" +
            "{width:72%!important;margin:8px auto 0!important;display:block!important;" +
            "border-radius:12px!important;overflow:hidden!important}"

    // Any real video card on the page means results are ready to show
    private const val READY_CHECK =
        "!!document.querySelector('ytm-video-with-context-renderer,ytm-compact-video-renderer," +
            "ytm-reel-item-renderer,ytm-rich-item-renderer,ytm-media-item,ytm-video-card-renderer')"

    private const val HOME = "https://m.youtube.com/"
    private const val RESULTS = "https://m.youtube.com/results?search_query="
}
