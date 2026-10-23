package com.abrar.watchtogether

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient

/**
 * The real TikTok feed inside the room. The person scrolls it like the TikTok app;
 * whichever reel is on screen (and whether it is playing) is reported, so everyone
 * else in the room gets the same reel in TikTok's official player.
 */
class TikTokMode(
    private val host: ViewGroup,
    private val onReel: (id: String, second: Float, playing: Boolean) -> Unit
) {
    private val main = Handler(Looper.getMainLooper())
    private val web = WebView(host.context)

    @SuppressLint("SetJavaScriptEnabled")
    fun start() {
        with(web.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, true)   // stay logged in
        web.setBackgroundColor(0xFF000000.toInt())
        web.addJavascriptInterface(Bridge(), "TTM")
        web.webViewClient = object : WebViewClient() {
            // Block "open in TikTok app" links (intent://, snssdk://…)
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val scheme = request.url.scheme ?: return true
                return scheme != "http" && scheme != "https"
            }

            override fun onPageCommitVisible(view: WebView, url: String) = inject(view)
            override fun onPageFinished(view: WebView, url: String) = inject(view)
        }
        host.addView(web, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        web.loadUrl("https://www.tiktok.com/foryou")
    }

    /** Someone else in the room paused or played: do the same on the feed. */
    fun setPlaying(play: Boolean) {
        web.evaluateJavascript("window.__wtTMctl&&window.__wtTMctl($play);", null)
    }

    fun stop() {
        (web.parent as? ViewGroup)?.removeView(web)
        web.stopLoading()
        web.destroy()
    }

    private fun inject(view: WebView) = view.evaluateJavascript(SCRIPT, null)

    private inner class Bridge {
        @JavascriptInterface
        fun state(id: String, second: Double, playing: Boolean) = main.post {
            onReel(id, second.toFloat(), playing)
        }
    }

    companion object {
        private val SCRIPT = """
            (function(){
              if (window.__wtTM) return; window.__wtTM = true;
              var RE = /(?:\/video\/|xgwrapper-\d+-)(\d{17,20})/;

              // The reel in the middle of the screen
              function current(){
                var cy = innerHeight / 2, best = null, bd = 1e9;
                document.querySelectorAll('video').forEach(function(v){
                  var r = v.getBoundingClientRect();
                  if (r.height < 80 || r.bottom <= 0 || r.top >= innerHeight) return;
                  var d = Math.abs((r.top + r.bottom) / 2 - cy);
                  if (d < bd) { bd = d; best = v; }
                });
                return best;
              }
              function idOf(v){
                for (var e = v, i = 0; e && e !== document.body && i < 12; e = e.parentElement, i++) {
                  var h = e.outerHTML || '';
                  if (h.length > 300000) break;
                  var m = RE.exec(h);
                  if (m) return m[1];
                }
                var u = RE.exec(location.href);
                return u ? u[1] : '';
              }

              var lastId = '', lastPaused = null, lastT = 0;
              setInterval(function(){
                var v = current(); if (!v) return;
                var id = idOf(v); if (!id) return;
                var t = v.currentTime || 0, p = v.paused;
                var expected = p ? lastT : lastT + 0.5;
                if (id !== lastId || p !== lastPaused || Math.abs(t - expected) > 2.5) TTM.state(id, t, !p);
                lastId = id; lastPaused = p; lastT = t;
              }, 500);

              window.__wtTMctl = function(play){
                var v = current(); if (!v) return;
                if (play) v.play().catch(function(){}); else v.pause();
              };

              // Hide "open the TikTok app" banners and boxes (never the login screens)
              var words = ['open tiktok', 'open app', 'open the app', 'get the app', 'get tiktok', 'download tiktok', 'download app'];
              function hideNags(){
                document.querySelectorAll('a,button,[role=button]').forEach(function(b){
                  var t = (b.innerText || '').trim().toLowerCase();
                  if (!t || t.length > 30 || !words.some(function(w){ return t.indexOf(w) >= 0; })) return;
                  for (var e = b; e && e !== document.body; e = e.parentElement) {
                    var pos = getComputedStyle(e).position;
                    if (pos === 'fixed' || pos === 'sticky' || e.getAttribute('role') === 'dialog') {
                      if (e.offsetWidth * e.offsetHeight < innerWidth * innerHeight * 0.85) e.style.setProperty('display','none','important');
                      break;
                    }
                  }
                });
              }
              setInterval(hideNags, 1000);
            })();
        """.trimIndent()
    }
}
