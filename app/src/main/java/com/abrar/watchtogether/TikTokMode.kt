package com.abrar.watchtogether

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONArray

/**
 * A TikTok feed running hidden behind the room. It is never shown (except for logging in);
 * it only tells the room which reel comes next. The reels themselves play in TikTok's
 * official player, in the same half-screen design as YouTube.
 */
class TikTokMode(
    private val root: ViewGroup,
    /** A new reel is on the hidden feed. */
    private val onReel: (id: String) -> Unit,
    /** All reels the feed has loaded so far, in order (for friends' swipe list). */
    private val onList: (List<String>) -> Unit,
    /** The feed stopped giving new reels (usually TikTok asking to log in). */
    private val onStuck: () -> Unit
) {
    private val main = Handler(Looper.getMainLooper())
    private val web = WebView(root.context)
    private var lastId = ""
    private var known: List<String> = emptyList()
    private var askedAt = 0L

    var loginVisible = false
        private set

    @SuppressLint("SetJavaScriptEnabled")
    fun start() {
        with(web.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = true
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
            override fun onPageFinished(view: WebView, url: String) {
                DebugLog.log("tiktok", "feed page: " + url.take(100))
                inject(view)
            }
        }
        hide()
        DebugLog.log("tiktok", "hidden feed start")
        web.loadUrl("https://www.tiktok.com/foryou")
    }

    /** Move the hidden feed one reel down (1) or up (-1). */
    fun step(dir: Int) {
        DebugLog.log("tiktok", "step $dir from $lastId")
        askedAt = SystemClock.elapsedRealtime()
        val before = lastId
        web.evaluateJavascript("window.__wtStep&&window.__wtStep($dir);", null)
        // If the feed itself didn't move, use the next reel it already loaded
        main.postDelayed({
            if (lastId != before) return@postDelayed
            val i = known.indexOf(before)
            val next = known.getOrNull(if (i < 0) 0 else i + dir)
            if (next != null && next != before) {
                lastId = next
                onReel(next)
            } else if (dir > 0) {
                DebugLog.log("tiktok", "stuck: feed did not move")
                onStuck()
            }
        }, 2500)
    }

    /** Show the TikTok page on top of the room so the person can log in. */
    fun showForLogin() {
        loginVisible = true
        (web.parent as? ViewGroup)?.removeView(web)
        root.addView(web, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        web.evaluateJavascript("window.__wtLogin=true;", null)
    }

    /** Back behind the room (after logging in). */
    fun hide() {
        loginVisible = false
        (web.parent as? ViewGroup)?.removeView(web)
        // Underneath everything: laid out (so the page loads) but covered by the player
        root.addView(web, 0, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        web.evaluateJavascript("window.__wtLogin=false;", null)
    }

    fun stop() {
        main.removeCallbacksAndMessages(null)
        (web.parent as? ViewGroup)?.removeView(web)
        web.stopLoading()
        web.destroy()
    }

    private fun inject(view: WebView) = view.evaluateJavascript(SCRIPT, null)

    private inner class Bridge {
        @JavascriptInterface
        fun current(id: String) = main.post {
            if (id == lastId) return@post
            DebugLog.log("tiktok", "feed reel $id")
            lastId = id
            onReel(id)
        }

        @JavascriptInterface
        fun list(json: String) = main.post {
            val ids = try {
                val a = JSONArray(json)
                (0 until a.length()).map { a.getString(it) }
            } catch (e: Exception) { emptyList() }
            if (ids.isNotEmpty() && ids != known) {
                DebugLog.log("tiktok", "feed knows ${ids.size} reels")
                known = ids
                onList(ids)
            }
        }
    }

    companion object {
        private val SCRIPT = """
            (function(){
              if (window.__wtTM) return; window.__wtTM = true;
              var RE = /(?:\/video\/|xgwrapper-\d+-)(\d{17,20})/;
              var REG = /(?:\/video\/|xgwrapper-\d+-)(\d{17,20})/g;

              // Silent: the reel plays in the room's player, not here
              setInterval(function(){
                if (window.__wtLogin) return;
                document.querySelectorAll('video,audio').forEach(function(m){ m.muted = true; if (!m.paused) m.pause(); });
              }, 300);

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
                return '';
              }
              var lastList = '';
              setInterval(function(){
                var v = current(); var id = v ? idOf(v) : '';
                if (id) TTM.current(id);
                var seen = {}, out = [], m, html = document.body ? document.body.innerHTML : '';
                REG.lastIndex = 0;
                while ((m = REG.exec(html)) && out.length < 100) { if (!seen[m[1]]) { seen[m[1]] = 1; out.push(m[1]); } }
                var s = JSON.stringify(out);
                if (s !== lastList) { lastList = s; TTM.list(s); }
              }, 600);

              // Next / previous reel: scroll the feed's own scroller one screen, with arrow keys as backup
              window.__wtStep = function(dir){
                var best = document.scrollingElement, bh = 0;
                document.querySelectorAll('div,main,section').forEach(function(e){
                  if (e.scrollHeight <= e.clientHeight + 50) return;
                  var oy = getComputedStyle(e).overflowY;
                  if ((oy === 'auto' || oy === 'scroll') && e.clientHeight > bh) { bh = e.clientHeight; best = e; }
                });
                var h = (best && best.clientHeight) || innerHeight;
                try { best.scrollBy({ top: dir * h, behavior: 'instant' }); } catch (x) { best.scrollTop += dir * h; }
                var key = dir > 0 ? 'ArrowDown' : 'ArrowUp';
                document.dispatchEvent(new KeyboardEvent('keydown', { key: key, code: key, keyCode: dir > 0 ? 40 : 38, bubbles: true }));
              };

              // Hide "open the TikTok app" boxes (never the login screens)
              var words = ['open tiktok', 'open app', 'open the app', 'get the app', 'get tiktok', 'download tiktok', 'download app', 'not now'];
              setInterval(function(){
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
              }, 1000);
            })();
        """.trimIndent()
    }
}
