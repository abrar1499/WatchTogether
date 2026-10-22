package com.abrar.watchtogether

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient

/**
 * Plays YouTube by opening the embed page directly in our own WebView.
 * Because the page is ours (not a cross-origin iframe), we can hide every bit of
 * YouTube's own UI with CSS and drive the <video> element ourselves.
 */
class EmbedPlayer(
    private val web: WebView,
    private val packageName: String,
    private val listener: Listener
) {
    enum class State { PLAYING, PAUSED, BUFFERING, ENDED }

    interface Listener {
        fun onState(state: State)
        fun onTime(second: Float)
        fun onDuration(duration: Float)
        fun onError(message: String)
    }

    private val main = Handler(Looper.getMainLooper())
    private var wantPlay = false
    private var startPaused = false
    private var fit = false
    private var full = false

    init {
        setup()
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setup() {
        with(web.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
        }
        web.setBackgroundColor(0xFF000000.toInt())
        web.isVerticalScrollBarEnabled = false
        web.isHorizontalScrollBarEnabled = false
        web.addJavascriptInterface(Bridge(), "WT")
        web.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String) {
                view.evaluateJavascript("window.__wtWantPlay=$wantPlay;$HOOK_JS", null)
                applyLayout()
            }

            // Never leave the embed page (e.g. a tap on the title would open youtube.com)
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                !request.url.toString().startsWith("https://www.youtube.com/embed/")
        }
    }

    /** Load a video. If [autoplay] is false it is paused at [start] once ready. */
    fun load(videoId: String, start: Float, autoplay: Boolean) {
        wantPlay = true          // let the page start so the video element is created
        startPaused = !autoplay
        val url = "https://www.youtube.com/embed/$videoId" +
            "?autoplay=1&controls=0&rel=0&iv_load_policy=3&playsinline=1&fs=0" +
            "&disablekb=1&modestbranding=1&cc_load_policy=0&start=${start.toInt()}"
        // YouTube refuses embeds without a Referer (error 153) or with youtube.com (error 152)
        web.loadUrl(url, mapOf("Referer" to "https://$packageName/"))
    }

    fun play() {
        wantPlay = true
        js("window.__wtWantPlay=true;var v=document.querySelector('video');if(v){v.play().catch(function(){});}")
    }

    fun pause() {
        wantPlay = false
        js("window.__wtWantPlay=false;var v=document.querySelector('video');if(v){v.pause();}")
    }

    fun seekTo(second: Float) {
        js("var v=document.querySelector('video');if(v){v.currentTime=$second;}")
    }

    /**
     * [fit] = show the whole video (letterboxed) instead of cropping to fill.
     * [full] = video fills the whole screen (landscape), no reflection.
     */
    fun setLayout(fit: Boolean, full: Boolean) {
        this.fit = fit
        this.full = full
        applyLayout()
    }

    private fun applyLayout() = js(
        "var c=document.documentElement.classList;" +
            "c.toggle('wt-fit',$fit);c.toggle('wt-full',$full);"
    )

    fun onPause() = web.onPause()
    fun onResume() = web.onResume()

    fun release() {
        web.stopLoading()
        web.destroy()
    }

    private fun js(code: String) = web.evaluateJavascript("(function(){$code})();", null)

    private inner class Bridge {
        @JavascriptInterface
        fun state(name: String) = main.post {
            val s = when (name) {
                "playing" -> State.PLAYING
                "paused" -> State.PAUSED
                "buffering" -> State.BUFFERING
                "ended" -> State.ENDED
                else -> return@post
            }
            // A "load paused" request: swallow the first start and pause right away
            if (s == State.PLAYING && startPaused) {
                startPaused = false
                pause()
                return@post
            }
            listener.onState(s)
        }

        @JavascriptInterface
        fun time(second: Double) = main.post { listener.onTime(second.toFloat()) }

        @JavascriptInterface
        fun duration(d: Double) = main.post { listener.onDuration(d.toFloat()) }

        @JavascriptInterface
        fun error(message: String) = main.post { listener.onError(message) }
    }

    companion object {
        // Everything YouTube draws on top of the video
        private const val HIDE_CSS =
            ".ytp-chrome-top,.ytp-chrome-bottom,.ytp-gradient-top,.ytp-gradient-bottom," +
                ".ytp-pause-overlay,.ytp-pause-overlay-container,.ytp-watermark,.ytp-youtube-button," +
                ".ytp-large-play-button,.ytp-title,.ytp-title-channel,.ytp-share-button," +
                ".ytp-overflow-button,.ytp-impression-link,.ytp-show-cards-title,.ytp-ce-element," +
                ".ytp-endscreen-content,.ytp-endscreen-previous,.ytp-endscreen-next,.videowall-endscreen," +
                ".ytp-cards-teaser,.ytp-cards-button,.ytp-paid-content-overlay,.ytp-suggested-action," +
                ".ytp-contextmenu,.ytp-popup,.ytp-tooltip,.branding-img,.iv-branding,.annotation," +
                ".ytp-chapter-container,.ytp-player-content.ytp-iv-player-content" +
                "{display:none!important;opacity:0!important;pointer-events:none!important}" +
                "html,body,#player{background:#000!important}" +
                // Video on the top half; its colours glow across the whole screen (ambient light)
                "html,body,#player,#movie_player,.html5-video-player,.html5-video-container" +
                "{overflow:visible!important;transform:none!important;contain:none!important}" +
                "#player,#movie_player,.html5-video-player,.html5-video-container{background:transparent!important}" +
                "video{position:fixed!important;top:0!important;left:0!important;" +
                "width:100vw!important;height:50vh!important;object-fit:cover!important;z-index:2!important;" +
                // the video's lower edge melts into the glow, so it feels like one screen
                "-webkit-mask-image:linear-gradient(#000 80%,transparent);mask-image:linear-gradient(#000 80%,transparent)}" +
                "html.wt-fit video{object-fit:contain!important}" +
                "html.wt-full video{height:100vh!important;-webkit-mask-image:none!important;mask-image:none!important}" +
                "#wtglow{position:fixed;left:-15vw;top:-10vh;width:130vw;height:120vh;z-index:1;pointer-events:none;" +
                "filter:blur(34px) saturate(1.8) brightness(1.05);opacity:.95}" +
                "#wtshade{position:fixed;left:0;top:0;width:100vw;height:100vh;z-index:3;pointer-events:none;" +
                "background:linear-gradient(rgba(0,0,0,0) 48%,rgba(0,0,0,.12) 65%,rgba(0,0,0,.5))}" +
                "html.wt-full #wtglow,html.wt-full #wtshade{display:none}"

        private val HOOK_JS = """
            (function(){
              if (window.__wt) return; window.__wt = true;
              var st = document.createElement('style');
              st.textContent = '$HIDE_CSS';
              (document.head || document.documentElement).appendChild(st);
              var glow = document.createElement('canvas'); glow.id = 'wtglow';
              glow.width = 24; glow.height = 48;
              var shade = document.createElement('div'); shade.id = 'wtshade';
              var root = document.body || document.documentElement;
              root.appendChild(glow); root.appendChild(shade);
              var gctx = glow.getContext('2d'), firstFrame = true;
              var hooked = null, errSent = false;
              function hook(v){
                hooked = v;
                v.addEventListener('playing', function(){ WT.state('playing'); });
                v.addEventListener('pause', function(){ WT.state('paused'); });
                v.addEventListener('waiting', function(){ WT.state('buffering'); });
                v.addEventListener('ended', function(){ window.__wtWantPlay = false; WT.state('ended'); });
                v.addEventListener('timeupdate', function(){ WT.time(v.currentTime); });
                v.addEventListener('durationchange', function(){
                  if (isFinite(v.duration) && v.duration > 0) WT.duration(v.duration);
                });
                if (isFinite(v.duration) && v.duration > 0) WT.duration(v.duration);
                if (!v.paused) WT.state('playing');
              }
              setInterval(function(){
                var v = document.querySelector('video');
                if (v && v !== hooked) hook(v);
                var err = document.querySelector('.ytp-error');
                if (err && !errSent && err.offsetParent !== null) {
                  errSent = true; WT.error((err.innerText || '').slice(0, 200));
                }
                // Autoplay can be blocked until the page is ready: keep nudging while we want playback
                if (window.__wtWantPlay) {
                  if (v && v.paused) { v.play().catch(function(){}); }
                  if (!v) { var b = document.querySelector('.ytp-large-play-button'); if (b) b.click(); }
                }
              }, 300);
              // Ambient glow: paint a tiny copy of the current frame ~15 times a second.
              // Blending with the previous frame makes the colours flow smoothly.
              setInterval(function(){
                if (!hooked || document.documentElement.classList.contains('wt-full')) return;
                if (hooked.readyState < 2) return;
                try {
                  gctx.globalAlpha = firstFrame ? 1 : 0.3;
                  gctx.drawImage(hooked, 0, 0, glow.width, glow.height);
                  firstFrame = false;
                } catch (e) {}
              }, 66);
            })();
        """.trimIndent()
    }
}
