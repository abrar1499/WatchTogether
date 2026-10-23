package com.abrar.watchtogether

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.GradientDrawable
import android.widget.LinearLayout
import com.abrar.watchtogether.databinding.ItemSiteTabBinding
import com.abrar.watchtogether.databinding.SheetYoutubeSearchBinding
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog

/**
 * YouTube search right inside the room: a sheet slides up with results,
 * and tapping any video plays it for everyone. The page itself is kept warm by [SearchWeb].
 */
class YouTubeSearchSheet(
    private val activity: Activity,
    private val initialQuery: String?,
    private val onPick: (String) -> Unit
) : BottomSheetDialog(activity, R.style.Theme_WatchTogether_Sheet) {

    private lateinit var b: SheetYoutubeSearchBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        b = SheetYoutubeSearchBinding.inflate(layoutInflater)
        setContentView(b.root)

        b.closeButton.setOnClickListener { dismiss() }
        b.searchInput.setOnEditorActionListener { _, id, _ ->
            if (id == EditorInfo.IME_ACTION_SEARCH) { search(b.searchInput.text.toString()); true } else false
        }
        b.searchButton.setOnClickListener { search(b.searchInput.text.toString()) }

        // A search typed on the room screen is always a YouTube search
        if (!initialQuery.isNullOrBlank()) SearchWeb.switchTo(Site.YOUTUBE)
        val web = SearchWeb.obtain(activity)
        // The page sits under a shimmering placeholder until real results are on it
        b.webHost.addView(web, 0, ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
        ))
        b.progress.visibility = View.GONE
        fun showSkeleton() {
            web.animate().cancel()
            web.alpha = 0f
            b.skeleton.animate().cancel()
            b.skeleton.alpha = 1f
            b.skeleton.visibility = View.VISIBLE
        }
        fun showResults() {
            web.animate().alpha(1f).setDuration(220).start()
            b.skeleton.animate().alpha(0f).setDuration(220)
                .withEndAction { b.skeleton.visibility = View.GONE }.start()
        }
        if (SearchWeb.contentReady && initialQuery.isNullOrBlank()) {
            web.alpha = 1f
            b.skeleton.visibility = View.GONE
        } else {
            showSkeleton()
        }
        SearchWeb.onLoadingStart = { showSkeleton() }
        SearchWeb.onContentReady = { showResults() }
        // Start the search right away, before the sheet has finished sliding up
        if (!initialQuery.isNullOrBlank()) {
            SearchWeb.search(initialQuery)
            if (SearchWeb.contentReady) showResults()   // same search as last time: already there
        }
        buildTabs()
        SearchWeb.onPick = { id ->
            onPick(id)
            dismiss()
        }
        setOnDismissListener { SearchWeb.release() }

        if (initialQuery.isNullOrBlank()) {
            b.searchInput.requestFocus()
            b.searchInput.postDelayed({ showKeyboard() }, 200)
        } else {
            b.searchInput.setText(initialQuery)
            b.searchInput.setSelection(initialQuery.length)
        }
    }

    override fun onStart() {
        super.onStart()
        // Sheet leaves the top of the video visible and stays open (scrolling the results shouldn't drag it closed)
        val sheet = findViewById<View>(com.google.android.material.R.id.design_bottom_sheet) ?: return
        val h = (context.resources.displayMetrics.heightPixels * RemoteConfig.sheetHeight).toInt()
        sheet.layoutParams.height = h
        sheet.setBackgroundColor(Color.TRANSPARENT)
        sheet.requestLayout()
        behavior.peekHeight = h
        behavior.skipCollapsed = true
        behavior.isDraggable = false
        behavior.state = BottomSheetBehavior.STATE_EXPANDED
    }

    private val tabViews = HashMap<Site, ItemSiteTabBinding>()

    /** YouTube / Netflix / Facebook / TikTok tabs above the search bar. */
    private fun buildTabs() {
        val gap = (8 * context.resources.displayMetrics.density).toInt()
        Site.values().forEachIndexed { i, site ->
            val t = ItemSiteTabBinding.inflate(layoutInflater, b.tabs, false)
            (t.root.layoutParams as LinearLayout.LayoutParams).marginStart = if (i == 0) 0 else gap
            t.label.text = site.label
            t.letter.text = site.label.take(1)
            t.letter.background = GradientDrawable().apply {
                cornerRadius = 6 * context.resources.displayMetrics.density
                setColor(site.color)
            }
            SearchWeb.icons[site]?.let { showIcon(t, it) } ?: loadIcon(site, t)
            t.root.setOnClickListener { select(site) }
            b.tabs.addView(t.root)
            tabViews[site] = t
        }
        markSelected()
    }

    private fun select(site: Site) {
        if (site == SearchWeb.site) return
        SearchWeb.switchTo(site)
        markSelected()
    }

    private fun markSelected() {
        tabViews.forEach { (site, t) -> t.root.isSelected = site == SearchWeb.site }
        b.searchInput.hint = context.tr(R.string.search_in, SearchWeb.site.label)
    }

    private fun showIcon(t: ItemSiteTabBinding, bmp: Bitmap) {
        t.icon.setImageBitmap(bmp)
        t.letter.visibility = View.INVISIBLE
    }

    /** Fetch the site's own icon, the same way a browser shows a tab icon. */
    private fun loadIcon(site: Site, t: ItemSiteTabBinding) {
        thread {
            val bmp = try {
                val conn = URL("https://www.google.com/s2/favicons?sz=64&domain=" + site.domain)
                    .openConnection() as HttpURLConnection
                conn.connectTimeout = 5000
                conn.readTimeout = 5000
                if (conn.responseCode == 200) conn.inputStream.use { BitmapFactory.decodeStream(it) } else null
            } catch (e: Exception) {
                null
            } ?: return@thread
            SearchWeb.icons[site] = bmp
            activity.runOnUiThread { if (isShowing) showIcon(t, bmp) }
        }
    }

    private fun search(query: String) {
        if (query.isBlank()) return
        hideKeyboard()
        SearchWeb.search(query)
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
