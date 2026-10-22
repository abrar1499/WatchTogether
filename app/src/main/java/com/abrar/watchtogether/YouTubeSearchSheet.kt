package com.abrar.watchtogether

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import com.abrar.watchtogether.databinding.SheetYoutubeSearchBinding
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import java.net.URLEncoder

/**
 * YouTube search right inside the room: a sheet slides up with results,
 * and tapping any video plays it for everyone.
 */
class YouTubeSearchSheet(
    context: Context,
    private val initialQuery: String?,
    private val onPick: (String) -> Unit
) : BottomSheetDialog(context, R.style.Theme_WatchTogether_Sheet) {

    private lateinit var b: SheetYoutubeSearchBinding
    private var picked = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        b = SheetYoutubeSearchBinding.inflate(layoutInflater)
        setContentView(b.root)

        b.closeButton.setOnClickListener { dismiss() }
        b.searchInput.setOnEditorActionListener { _, id, _ ->
            if (id == EditorInfo.IME_ACTION_SEARCH) { search(b.searchInput.text.toString()); true } else false
        }
        b.searchButton.setOnClickListener { search(b.searchInput.text.toString()) }

        with(b.web.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = true
        }
        b.web.setBackgroundColor(Color.parseColor("#141416"))
        b.web.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, newProgress: Int) {
                b.progress.visibility = if (newProgress < 100) View.VISIBLE else View.INVISIBLE
                b.progress.progress = newProgress
            }
        }
        b.web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (tryPick(request.url.toString())) return true
                // Block "open in YouTube app" style links (intent://, vnd.youtube://)
                val scheme = request.url.scheme ?: return true
                return scheme != "http" && scheme != "https"
            }

            // YouTube's mobile site changes pages without reloading, so watch the history too
            override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) {
                tryPick(url)
            }

            override fun onPageFinished(view: WebView, url: String) {
                // Hide YouTube's own top bar and bottom tabs; our search bar replaces them
                view.evaluateJavascript(
                    "(function(){var s=document.createElement('style');s.textContent=" +
                        "'ytm-mobile-topbar-renderer,#header-bar,.mobile-topbar-header,ytm-pivot-bar-renderer," +
                        "ytm-feed-filter-chip-bar-renderer{display:none!important}" +
                        "body,ytm-app{padding-top:0!important}';document.head.appendChild(s);})();",
                    null
                )
            }
        }

        setOnDismissListener {
            b.web.stopLoading()
            b.web.destroy()
        }

        if (initialQuery.isNullOrBlank()) {
            b.web.loadUrl("https://m.youtube.com/")
            b.searchInput.requestFocus()
            b.searchInput.postDelayed({ showKeyboard() }, 250)
        } else {
            b.searchInput.setText(initialQuery)
            b.searchInput.setSelection(initialQuery.length)
            search(initialQuery)
        }
    }

    override fun onStart() {
        super.onStart()
        // Tall sheet that stays open (scrolling the results shouldn't drag it closed)
        val sheet = findViewById<View>(com.google.android.material.R.id.design_bottom_sheet) ?: return
        val h = (context.resources.displayMetrics.heightPixels * 0.88).toInt()
        sheet.layoutParams.height = h
        sheet.setBackgroundColor(Color.TRANSPARENT)
        sheet.requestLayout()
        behavior.peekHeight = h
        behavior.skipCollapsed = true
        behavior.isDraggable = false
        behavior.state = BottomSheetBehavior.STATE_EXPANDED
    }

    private fun search(query: String) {
        val q = query.trim()
        if (q.isEmpty()) return
        hideKeyboard()
        b.web.loadUrl("https://m.youtube.com/results?search_query=" + URLEncoder.encode(q, "UTF-8"))
    }

    private fun tryPick(url: String): Boolean {
        if (picked) return true
        val isVideoPage = url.contains("/watch") || url.contains("/shorts/")
        if (!isVideoPage) return false
        val id = YouTubeLink.extractId(url) ?: return false
        picked = true
        b.web.stopLoading()
        onPick(id)
        dismiss()
        return true
    }

    private fun showKeyboard() {
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.showSoftInput(b.searchInput, InputMethodManager.SHOW_IMPLICIT)
    }

    private fun hideKeyboard() {
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        imm.hideSoftInputFromWindow(b.searchInput.windowToken, 0)
        b.searchInput.clearFocus()
    }
}
