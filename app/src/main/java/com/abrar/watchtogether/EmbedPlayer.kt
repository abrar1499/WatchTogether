package com.abrar.watchtogether

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONObject

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
        /** Fraction of the screen height the video takes (from the top). */
        fun onVideoArea(fraction: Float)
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
            override fun onPageCommitVisible(view: WebView, url: String) {
                view.evaluateJavascript("window.__wtWantPlay=$wantPlay;" + hookJs(), null)
                applyLayout()
            }

            override fun onPageFinished(view: WebView, url: String) {
                view.evaluateJavascript("window.__wtWantPlay=$wantPlay;" + hookJs(), null)
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
            "c.toggle('wt-fit',$fit);c.toggle('wt-full',$full);" +
            "if(window.__wtRelayout)window.__wtRelayout();"
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

        @JavascriptInterface
        fun area(fraction: Double) = main.post { listener.onVideoArea(fraction.toFloat()) }
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
                ".ytp-chapter-container,.ytp-player-content.ytp-iv-player-content," +
                ".ytp-spinner,.ytp-cued-thumbnail-overlay,.ytp-bezel,.ytp-bezel-text,.ytp-autonav-endscreen" +
                "{display:none!important;opacity:0!important;pointer-events:none!important}" +
                // Catch-all: inside the player, show only the video (YouTube's new UI uses new names)
                "#movie_player>*:not(.html5-video-container):not(.ytp-error),.html5-video-container>*:not(video){display:none!important;opacity:0!important;pointer-events:none!important}" +
                "html{background:#000!important}body,#player,#movie_player,.html5-video-player,.html5-video-container{background:transparent!important}" +
                // Video on the top half, a mirrored reflection on the bottom half
                "html,body,#player,#movie_player,.html5-video-player,.html5-video-container" +
                "{overflow:visible!important;transform:none!important;contain:none!important}" +
                "video{position:fixed!important;top:0!important;left:0!important;" +
                "width:100vw!important;height:var(--wt-h,50vh)!important;object-fit:cover!important;z-index:1!important;" +
                // Reflection is strongest right at the seam and fades downwards
                "-webkit-box-reflect:below 0px linear-gradient(rgba(255,255,255,.25),rgba(255,255,255,.6) 45%,#fff)}" +
                "html.wt-fit video{object-fit:contain!important}" +
                "html.wt-full video{height:100vh!important;-webkit-box-reflect:none}" +
                // Progressive blur: starts gently inside the video's lower part, so there is no hard line
                ".wtfrost{position:fixed;left:0;width:100vw;pointer-events:none}" +
                "#wtfrost1{top:calc(var(--wt-h,50vh)*0.76);bottom:0;z-index:2;" +
                "-webkit-backdrop-filter:blur(5px) saturate(1.3);backdrop-filter:blur(5px) saturate(1.3);" +
                "-webkit-mask-image:linear-gradient(transparent,#000 20%);mask-image:linear-gradient(transparent,#000 20%)}" +
                "#wtfrost2{top:calc(var(--wt-h,50vh)*0.88);bottom:0;z-index:3;" +
                "-webkit-backdrop-filter:blur(12px) saturate(1.6);backdrop-filter:blur(12px) saturate(1.6);" +
                "-webkit-mask-image:linear-gradient(transparent,#000 22%);mask-image:linear-gradient(transparent,#000 22%)}" +
                "#wtfrost3{top:calc(var(--wt-h,50vh)*1);bottom:0;z-index:4;" +
                "-webkit-backdrop-filter:blur(22px) saturate(1.9) brightness(1.1);backdrop-filter:blur(22px) saturate(1.9) brightness(1.1);" +
                "-webkit-mask-image:linear-gradient(transparent,#000 30%);mask-image:linear-gradient(transparent,#000 30%);" +
                "background:linear-gradient(rgba(0,0,0,0),rgba(0,0,0,.1) 50%,rgba(0,0,0,.45))}" +
                "html.wt-full .wtfrost{display:none}" +
                // Soft colour glow behind everything, so the space below a short video isn't empty
                "#wtglow{position:fixed;left:-10vw;top:-10vh;width:120vw;height:120vh;z-index:-1;pointer-events:none;filter:blur(40px) saturate(1.6);opacity:.85}html.wt-full #wtglow{display:none}" +
                // Bulletproof: hide everything YouTube draws, whatever it's called; show only the video
                "body *{visibility:hidden!important}video,.wtfrost,#wtshade,#wtglow,#wtfrost1,#wtfrost2,#wtfrost3{visibility:visible!important}"

        /** Hook script with the current look (from [RemoteConfig] if available). */
        private fun hookJs(): String =
            HOOK_JS.replace("__WT_CSS__", JSONObject.quote(RemoteConfig.playerCss ?: HIDE_CSS))

        private val HOOK_JS = """
            (function(){
              if (window.__wt) return; window.__wt = true;
              var st = document.createElement('style');
              st.textContent = __WT_CSS__;
              (document.head || document.documentElement).appendChild(st);
              ['wtfrost1','wtfrost2','wtfrost3'].forEach(function(id){
                var fr = document.createElement('div'); fr.id = id; fr.className = 'wtfrost';
                (document.body || document.documentElement).appendChild(fr);
              });
              var glow = document.createElement('canvas'); glow.id = 'wtglow';
              glow.width = 24; glow.height = 48;
              (document.body || document.documentElement).appendChild(glow);
              var gctx = glow.getContext('2d'), firstFrame = true;
              var hooked = null, errSent = false;
              // Fit: full width at the video's own shape (never cropped), at most half the screen.
              // Fill: always half the screen (cropped). Full screen: whole screen.
              function relayout(){
                var de = document.documentElement, W = innerWidth, H = innerHeight;
                var v = hooked || document.querySelector('video');
                var h = H * 0.5;
                if (de.classList.contains('wt-full')) h = H;
                else if (de.classList.contains('wt-fit') && v && v.videoWidth > 0)
                  h = Math.min(W * v.videoHeight / v.videoWidth, H * 0.5);
                de.style.setProperty('--wt-h', h + 'px');
                WT.area(h / H);
              }
              window.__wtRelayout = relayout;
              addEventListener('resize', relayout);
              function hook(v){
                hooked = v;
                v.addEventListener('playing', function(){ WT.state('playing'); });
                v.addEventListener('pause', function(){ WT.state('paused'); });
                v.addEventListener('waiting', function(){ WT.state('buffering'); });
                v.addEventListener('ended', function(){ window.__wtWantPlay = false; WT.state('ended'); });
                v.addEventListener('timeupdate', function(){ WT.time(v.currentTime); });
                v.addEventListener('loadedmetadata', relayout);
                v.addEventListener('resize', relayout);
                v.addEventListener('durationchange', function(){
                  if (isFinite(v.duration) && v.duration > 0) WT.duration(v.duration);
                });
                if (isFinite(v.duration) && v.duration > 0) WT.duration(v.duration);
                if (!v.paused) WT.state('playing');
                relayout();
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
              // Glow: a tiny copy of the current frame, blended with the last one so colours flow
              setInterval(function(){
                if (!hooked || hooked.readyState < 2) return;
                if (document.documentElement.classList.contains('wt-full')) return;
                try {
                  gctx.globalAlpha = firstFrame ? 1 : 0.3;
                  gctx.drawImage(hooked, 0, 0, glow.width, glow.height);
                  firstFrame = false;
                } catch (e) {}
              }, 80);
            })();
        """.trimIndent()
    }
}
