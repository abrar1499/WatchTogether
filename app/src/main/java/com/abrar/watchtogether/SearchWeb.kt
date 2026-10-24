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
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
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

    private fun isAppStoreHost(host: String): Boolean {
        val h = host.lowercase()
        return h == "play.google.com" || h.endsWith(".play.google.com") ||
            h == "apps.apple.com" || h.endsWith(".apps.apple.com") ||
            h == "itunes.apple.com" || h.endsWith(".itunes.apple.com")
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
        // TikTok login relies on persistent cookies, including third-party auth cookies.
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(v, true)
        v.isFocusable = true
        v.isFocusableInTouchMode = true
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
                val scheme = request.url.scheme ?: return true
                if (scheme != "http" && scheme != "https") return true
                if (site == Site.TIKTOK && isAppStoreHost(request.url.host.orEmpty())) return true
                return false
            }

            // TikTok sometimes opens its app-install page through a redirect or an embedded frame.
            // Block those requests too; shouldOverrideUrlLoading alone doesn't cover every redirect.
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                if (site == Site.TIKTOK && isAppStoreHost(request.url.host.orEmpty())) {
                    return WebResourceResponse(
                        "text/plain", "UTF-8",
                        java.io.ByteArrayInputStream(ByteArray(0))
                    )
                }
                return null
            }

            // YouTube's mobile site changes pages without reloading, so watch the history too
            override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) {
                tryPick(view, url, fromHistory = true)
            }

            override fun onPageCommitVisible(view: WebView, url: String) {
                injectCss(view)
                if (site != Site.TIKTOK) removeAppNags(view)
                watchTaps(view)
            }
            override fun onPageFinished(view: WebView, url: String) {
                injectCss(view)
                if (site != Site.TIKTOK) removeAppNags(view)
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
              // Search all nearby links instead of stopping at a non-video wrapper link.
              // TikTok cards often nest the video link inside several clickable containers.
              function linkOf(t){
                for (var e = t, depth = 0; e && e !== document && depth < 30; e = e.parentElement, depth++) {
                  var candidates = [];
                  try { if (e.href && typeof e.href === 'string') candidates.push(e.href); } catch(x){}
                  if (e.getAttribute) {
                    ['href','data-href','data-url','data-video-url','data-link'].forEach(function(k){
                      var h = e.getAttribute(k);
                      if (h) { try { candidates.push(new URL(h, location.href).href); } catch(x) { candidates.push(h); } }
                    });
                  }
                  for (var i = 0; i < candidates.length; i++) {
                    if (WTS.isVideo(candidates[i])) return candidates[i];
                  }
                  // Some TikTok cards store the item ID in data attributes rather than an href.
                  if (PAT && /tiktok/.test(location.host) && e.attributes) {
                    for (var j = 0; j < e.attributes.length; j++) {
                      var raw = e.attributes[j].value || '';
                      var m = PAT.re.exec(raw);
                      if (m) return PAT.url + m[1];
                      m = /(?:itemId|item_id|videoId|video_id|aweme_id)["']?\s*[:=]\s*["']?(\d{17,20})/i.exec(raw);
                      if (m) return PAT.url + m[1];
                    }
                  }
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
                ? { re: /(?:\/video\/|xgwrapper-\d+-)(\d{17,20})/, url: 'https://www.tiktok.com/video/' }
                : /facebook/.test(host)
                ? { re: /(?:\/reel\/|\/videos\/(?:[^\/"&]+\/)?|watch\/?\?v=|video_id=|data-video-id="|(?:videoID|video_id|videoId)(?:"|&quot;):(?:"|&quot;))(\d{8,20})/, url: 'https://www.facebook.com/watch/?v=' }
                : null;
              // The video under the finger (feeds stack many videos on one page)
              function videoAt(x, y){
                var best = null;
                document.querySelectorAll('video').forEach(function(v){
                  var r = v.getBoundingClientRect();
                  if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) best = best || v;
                });
                return best;
              }
              function idUrlOf(t){
                if (!PAT || !t) return '';
                for (var e = t, i = 0; e && e !== document.body && i < 30; e = e.parentElement, i++) {
                  // Check URLs/data attributes first; a full card's outerHTML can be very large.
                  if (e.getAttribute) {
                    var names = ['href','data-href','data-url','data-video-id','data-item-id','data-id','id'];
                    for (var j = 0; j < names.length; j++) {
                      var raw = e.getAttribute(names[j]) || '';
                      var m = PAT.re.exec(raw);
                      if (m) return PAT.url + m[1];
                      if (/tiktok/.test(location.host)) {
                        m = /(?:itemId|item_id|videoId|video_id|aweme_id)["']?\s*[:=]\s*["']?(\d{17,20})/i.exec(raw);
                        if (m) return PAT.url + m[1];
                      }
                    }
                  }
                  var html = e.outerHTML || '';
                  // Keep scanning parents even if one contains a huge subtree.
                  if (html.length > 600000) html = html.slice(0, 600000);
                  var m = PAT.re.exec(html);
                  if (m) return PAT.url + m[1];
                  if (/tiktok/.test(location.host)) {
                    m = /(?:itemId|item_id|videoId|video_id|aweme_id)["']?\s*[:=]\s*["']?(\d{17,20})/i.exec(html);
                    if (m) return PAT.url + m[1];
                  }
                }
                return '';
              }
              function isStoreUrl(href){
                try {
                  var u = new URL(href, location.href), h = (u.host || '').toLowerCase();
                  return h === 'play.google.com' || h.endsWith('.play.google.com') ||
                    h === 'apps.apple.com' || h.endsWith('.apps.apple.com') ||
                    h === 'itunes.apple.com' || h.endsWith('.itunes.apple.com');
                } catch(x) { return false; }
              }
              function rawLinkOf(t){
                for (var e = t, depth = 0; e && e !== document && depth < 30; e = e.parentElement, depth++) {
                  if (e.href && typeof e.href === 'string') return e.href;
                  if (e.getAttribute) {
                    var h = e.getAttribute('href') || e.getAttribute('data-href') || e.getAttribute('data-url');
                    if (h) { try { return new URL(h, location.href).href; } catch(x) { return h; } }
                  }
                }
                return '';
              }
              function videoHrefAt(target, x, y, ev){
                function normal(h){
                  if (!h) return '';
                  try { h = new URL(h, location.href).href; } catch(x) {}
                  return WTS.isVideo(h) ? h : '';
                }
                function isUiLayer(n){
                  if (!n || n.nodeType !== 1 || !n.matches) return false;
                  return n.matches(
                    'button,input,textarea,select,option,label,nav,header,[role="tab"],' +
                    '[role="dialog"],[aria-modal="true"],[data-e2e*="close" i],' +
                    '[aria-label*="close" i],[aria-label*="back" i],' +
                    '[class*="modal" i],[class*="drawer" i],[class*="description" i],' +
                    '[data-e2e*="description" i]'
                  );
                }

                // Never hijack TikTok's own navigation, modal/description sheet, or its close button.
                // Check the complete composed path because some controls are rendered in shadow roots.
                var path = (ev && ev.composedPath) ? ev.composedPath() : [];
                for (var p = 0; p < path.length; p++) {
                  var n = path[p];
                  if (!n || n.nodeType !== 1) continue;
                  if (isUiLayer(n)) return '';
                  if (n.tagName === 'A') {
                    var raw = n.href || n.getAttribute('href') || '';
                    return normal(raw); // A non-video link belongs to TikTok; let it navigate normally.
                  }
                }

                // If the target belongs to a link, respect that link instead of searching its parents.
                var anchor = target && target.closest ? target.closest('a[href]') : null;
                if (anchor) return normal(anchor.href);

                // Some grid thumbnails expose the link on a surrounding tile. Only accept an anchor
                // whose visible rectangle actually contains the tap point; never pick a nearby tile.
                for (var e = target, depth = 0; e && e !== document.body && depth < 10; e = e.parentElement, depth++) {
                  if (isUiLayer(e)) return '';
                  if (!e.querySelectorAll) continue;
                  var links = e.querySelectorAll('a[href*="/video/"],a[href*="xgwrapper-"]');
                  for (var i = 0; i < Math.min(links.length, 40); i++) {
                    var h = normal(links[i].href);
                    if (!h) continue;
                    var r = links[i].getBoundingClientRect();
                    if (r.width > 0 && r.height > 0 &&
                        x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) return h;
                  }
                }

                // A tap on the actual video element can be resolved from its own item's markup.
                // Do not scan arbitrary page ancestors: that was selecting a video on every tap.
                var v = videoAt(x, y);
                if (v && (target === v || (v.contains && v.contains(target)) ||
                    (target && target.contains && target.contains(v)))) {
                  var videoUrl = idUrlOf(v);
                  if (videoUrl && WTS.isVideo(videoUrl)) return videoUrl;
                }
                return '';
              }
              function choose(href){
                sendList();
                WTS.pick(href);
              }

              // Only intercept actual video tiles. Profile/feed navigation and modal controls stay native.
              // Listening in capture phase lets us select a video before TikTok navigates to it.
              var sx = 0, sy = 0, st = 0, handledAt = 0;
              document.addEventListener('touchstart', function(ev){
                var t = ev.touches[0]; if (!t) return;
                sx = t.clientX; sy = t.clientY; st = Date.now();
              }, { capture: true, passive: true });
              // Stop TikTok's app-install CTA from opening the Play Store inside the search sheet.
              // Preserve normal web navigation for other destinations.
              var oldOpen = window.open;
              window.open = function(url) {
                if (isStoreUrl(String(url || ''))) return null;
                return oldOpen ? oldOpen.apply(window, arguments) : null;
              };

              document.addEventListener('touchend', function(ev){
                var t = ev.changedTouches[0]; if (!t) return;
                // Only a short, still tap (not a scroll or swipe)
                if (Math.abs(t.clientX - sx) > 12 || Math.abs(t.clientY - sy) > 12 || Date.now() - st > 500) return;
                var target = document.elementFromPoint(t.clientX, t.clientY) || ev.target;
                var raw = rawLinkOf(target);
                if (isStoreUrl(raw)) {
                  ev.preventDefault(); ev.stopPropagation(); ev.stopImmediatePropagation();
                  handledAt = Date.now(); return;
                }
                var href = videoHrefAt(target, t.clientX, t.clientY, ev);
                if (!href) return;
                ev.preventDefault(); ev.stopPropagation(); ev.stopImmediatePropagation();
                handledAt = Date.now();
                choose(href);
              }, { capture: true, passive: false });

              document.addEventListener('click', function(ev){
                if (Date.now() - handledAt < 800) { ev.preventDefault(); ev.stopPropagation(); ev.stopImmediatePropagation(); return; }
                var raw = rawLinkOf(ev.target);
                if (isStoreUrl(raw)) {
                  ev.preventDefault(); ev.stopPropagation(); ev.stopImmediatePropagation();
                  handledAt = Date.now(); return;
                }
                var href = videoHrefAt(ev.target, ev.clientX, ev.clientY, ev);
                if (!href) return;
                ev.preventDefault(); ev.stopPropagation(); ev.stopImmediatePropagation();
                choose(href);
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
                // TikTok owns its scrolling and login form. Never rewrite its layout or hide its dialog.
                if (/tiktok\.com$/i.test(location.hostname)) return;
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
                if (/tiktok\.com$/i.test(location.hostname)) return;
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
