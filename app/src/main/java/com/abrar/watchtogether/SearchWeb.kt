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
import android.webkit.JavascriptInterface
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
    private var defaultUa: String? = null

    /** The site currently open in the search sheet. */
    var site = Site.YOUTUBE
        private set

    /** Each site's own icon, fetched from the site (like a browser tab icon). */
    val icons = HashMap<Site, android.graphics.Bitmap>()

    var onPick: ((String) -> Unit)? = null

    /** All videos on the page the last pick came from, in order (becomes the room's swipe list). */
    var lastList: List<String> = emptyList()
        private set
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
        v.settings.userAgentString = if (site == Site.NETFLIX) Media.DESKTOP_UA else defaultUa
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
        defaultUa = v.settings.userAgentString
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
        v.addJavascriptInterface(TapBridge(v), "WTS")
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

            override fun onPageCommitVisible(view: WebView, url: String) {
                injectCss(view)
                removeAppNags(view)
                watchTaps(view)
            }
            override fun onPageFinished(view: WebView, url: String) {
                injectCss(view)
                removeAppNags(view)
                watchTaps(view)
            }
        }
        return v
    }

    private fun tryPick(view: WebView, url: String, fromHistory: Boolean): Boolean {
        val key = Media.keyFromUrl(site, url) ?: return false
        if (picked) return true
        picked = true
        // Don't let the site start that video in the background; go back to the list
        stopMedia(view)
        if (fromHistory) view.evaluateJavascript("history.back();", null)
        onPick?.invoke(key)
        return true
    }

    /** Called from the page: is this link a video we can play in the room? */
    private class TapBridge(val view: WebView) {
        @JavascriptInterface
        fun isVideo(href: String): Boolean = Media.keyFromUrl(site, href) != null

        @JavascriptInterface
        fun pick(href: String) {
            main.post { tryPick(view, href, fromHistory = false) }
        }

        /** The page's video links in order; turned into room keys. */
        @JavascriptInterface
        fun list(json: String) {
            val keys = try {
                val arr = org.json.JSONArray(json)
                (0 until arr.length()).mapNotNull { Media.keyFromUrl(site, arr.optString(it)) }.distinct()
            } catch (e: Exception) { emptyList() }
            main.post { lastList = keys.take(60) }
        }
    }

    /**
     * TikTok and Facebook often play a video right on the page without changing the address.
     * Catch the tap itself (and any quiet address change) and send the video to the room instead.
     */
    private fun watchTaps(view: WebView) {
        view.evaluateJavascript(
            """
            (function(){
              if (window.__wtTaps) return; window.__wtTaps = true;
              function linkOf(t){
                for (var e = t; e && e !== document; e = e.parentElement) {
                  if (e.href && typeof e.href === 'string') return e.href;
                  var h = e.getAttribute && (e.getAttribute('href') || e.getAttribute('data-href'));
                  if (h) { try { return new URL(h, location.href).href; } catch(x){} }
                }
                return '';
              }
              function sendList(){
                var seen = {}, out = [];
                document.querySelectorAll('a[href]').forEach(function(a){
                  var h = a.href; if (!h || seen[h]) return; seen[h] = 1;
                  if (WTS.isVideo(h)) out.push(h);
                });
                // Plus every video number in a feed, in page order
                if (PAT) {
                  var g = new RegExp(PAT.re.source, 'g'), m, html = document.body.innerHTML;
                  while ((m = g.exec(html)) && out.length < 80) {
                    var u = PAT.url + m[1]; if (!seen[u]) { seen[u] = 1; out.push(u); }
                  }
                }
                WTS.list(JSON.stringify(out));
              }
              // Feeds (TikTok, Facebook Reels) play videos without links: find the video's number
              // in the tapped card's own markup instead
              var host = location.host;
              var PAT = /tiktok/.test(host)
                ? { re: /(?:\/video\/|xgwrapper-\d+-|"id":")(\d{17,20})/, url: 'https://www.tiktok.com/video/' }
                : /facebook/.test(host)
                ? { re: /(?:\/reel\/|\/videos\/|video_id=|"videoID":"|"video_id":")(\d{8,20})/, url: 'https://www.facebook.com/watch/?v=' }
                : null;
              function idUrlOf(t){
                if (!PAT) return '';
                for (var e = t, i = 0; e && e !== document.body && i < 12; e = e.parentElement, i++) {
                  var html = e.outerHTML || '';
                  if (html.length > 300000) break;
                  var m = PAT.re.exec(html);
                  if (m) return PAT.url + m[1];
                }
                return '';
              }
              document.addEventListener('click', function(ev){
                var href = linkOf(ev.target);
                if (!href || !WTS.isVideo(href)) href = idUrlOf(ev.target) || href;
                if (href && WTS.isVideo(href)) {
                  ev.preventDefault(); ev.stopPropagation();
                  sendList();
                  WTS.pick(href);
                }
              }, true);
              var last = location.href;
              setInterval(function(){
                if (location.href !== last) {
                  last = location.href;
                  if (WTS.isVideo(last)) { sendList(); WTS.pick(last); }
                }
              }, 400);
            })();
            """.trimIndent(),
            null
        )
    }

    private fun stopMedia(view: WebView) {
        view.evaluateJavascript(
            "document.querySelectorAll('video,audio').forEach(function(m){try{m.pause();m.muted=true;}catch(e){}});",
            null
        )
    }

    // Hide YouTube's own top bar and bottom tabs; our search bar replaces them
    /**
     * Sites keep popping up "Open the app" boxes. Find any button with such text,
     * hide the floating box around it and the dark layer behind it, and unlock scrolling.
     */
    private fun removeAppNags(view: WebView) {
        val phrases = JSONObject.wrap(RemoteConfig.nagPhrases.map { it.lowercase() }).toString()
        view.evaluateJavascript(
            """
            (function(){
              window.__wtPhrases = $phrases;
              if (window.__wtNag) return; window.__wtNag = true;
              // The nearest floating box around the button, but never a box that is basically the whole page
              function popupBox(el){
                for (var e = el; e && e !== document.body; e = e.parentElement) {
                  var p = getComputedStyle(e).position;
                  var floating = p === 'fixed' || p === 'sticky' || e.getAttribute('role') === 'dialog' || e.getAttribute('aria-modal') === 'true';
                  if (!floating) continue;
                  var big = e.offsetWidth * e.offsetHeight > innerWidth * innerHeight * 0.85;
                  var busy = e.querySelectorAll('a').length > 12 || e.querySelector('video');
                  if (big && busy) return null;          // that's the app itself, leave it
                  return e;
                }
                return null;
              }
              function clean(){
                var words = window.__wtPhrases || [], hid = false;
                document.querySelectorAll('a,button,[role=button],span,div[tabindex]').forEach(function(b){
                  var t = (b.innerText || '').trim().toLowerCase();
                  if (!t || t.length > 40) return;
                  if (!words.some(function(w){ return t.indexOf(w) >= 0; })) return;
                  var box = popupBox(b);
                  if (!box) return;
                  if (box.style.display !== 'none') { box.style.setProperty('display','none','important'); hid = true; }
                });
                // A dark full-screen layer left in the middle of the screen
                var mid = document.elementFromPoint(innerWidth/2, innerHeight/2);
                for (var e = mid; e && e !== document.body; e = e.parentElement) {
                  var cs = getComputedStyle(e);
                  if (cs.position === 'fixed' && e.offsetWidth >= innerWidth*0.9 && e.offsetHeight >= innerHeight*0.6 &&
                      !(e.innerText || '').trim() && !e.querySelector('video,img,canvas') && e.children.length < 3) {
                    e.style.setProperty('display','none','important'); hid = true; break;
                  }
                }
                if (hid) {
                  [document.documentElement, document.body].forEach(function(x){
                    x.style.setProperty('overflow','auto','important');
                    x.style.setProperty('position','static','important');
                  });
                }
              }
              // Previews in the search sheet stay silent
              document.addEventListener('play', function(ev){ try { ev.target.muted = true; } catch(e){} }, true);
              setInterval(function(){
                document.querySelectorAll('video,audio').forEach(function(m){ if (!m.muted) m.muted = true; });
              }, 500);
              clean();
              var n = 0, fast = setInterval(function(){ clean(); if (++n > 25) { clearInterval(fast); setInterval(clean, 2500); } }, 400);
            })();
            """.trimIndent(),
            null
        )
    }

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
            // Full-width but shorter thumbnails, so more results fit
            ".media-item-thumbnail-container,.video-thumbnail-container-large,ytm-thumbnail-cover" +
            "{aspect-ratio:21/9!important;height:auto!important;padding-top:0!important;overflow:hidden!important}" +
            ".media-item-thumbnail-container img,.video-thumbnail-container-large img,ytm-thumbnail-cover img," +
            ".video-thumbnail-img{width:100%!important;height:100%!important;object-fit:cover!important;" +
            "position:absolute!important;inset:0!important}"

    // Any real video card on the page means results are ready to show
    private const val READY_CHECK =
        "!!document.querySelector('ytm-video-with-context-renderer,ytm-compact-video-renderer," +
            "ytm-reel-item-renderer,ytm-rich-item-renderer,ytm-media-item,ytm-video-card-renderer')"

    private const val HOME = "https://m.youtube.com/"
    private const val RESULTS = "https://m.youtube.com/results?search_query="
}
