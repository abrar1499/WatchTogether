package com.abrar.watchtogether

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import com.abrar.watchtogether.databinding.ActivityYoutubeBrowseBinding

/**
 * Shows the YouTube mobile site inside the app. As soon as the user taps a video,
 * we grab its id and send it back to the room, so nobody has to copy-paste links.
 */
class YouTubeBrowseActivity : AppCompatActivity() {

    private lateinit var b: ActivityYoutubeBrowseBinding
    private var picked = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        b = ActivityYoutubeBrowseBinding.inflate(layoutInflater)
        setContentView(b.root)

        b.closeButton.setOnClickListener { finish() }

        with(b.web.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = true
        }

        b.web.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, newProgress: Int) {
                b.progress.visibility = if (newProgress < 100) View.VISIBLE else View.GONE
                b.progress.progress = newProgress
            }
        }

        b.web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val url = request.url.toString()
                if (tryPick(url)) return true
                // Block "open in YouTube app" style links (intent://, vnd.youtube://)
                val scheme = request.url.scheme ?: return true
                return scheme != "http" && scheme != "https"
            }

            // YouTube's mobile site changes pages without reloading, so watch the history too
            override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) {
                tryPick(url)
            }
        }

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (b.web.canGoBack()) b.web.goBack() else finish()
            }
        })

        if (savedInstanceState == null) b.web.loadUrl("https://m.youtube.com/")
        else b.web.restoreState(savedInstanceState)
    }

    private fun tryPick(url: String): Boolean {
        if (picked) return true
        val isVideoPage = url.contains("/watch") || url.contains("/shorts/")
        if (!isVideoPage) return false
        val id = YouTubeLink.extractId(url) ?: return false
        picked = true
        b.web.stopLoading()
        b.web.onPause()
        setResult(Activity.RESULT_OK, Intent().putExtra(EXTRA_VIDEO_ID, id))
        finish()
        return true
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        b.web.saveState(outState)
    }

    override fun onDestroy() {
        b.web.destroy()
        super.onDestroy()
    }

    companion object {
        const val EXTRA_VIDEO_ID = "video_id"
    }
}
