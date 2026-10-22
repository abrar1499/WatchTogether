package com.abrar.watchtogether

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import com.abrar.watchtogether.databinding.SheetYoutubeSearchBinding
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

        b.searchInput.hintR(R.string.search_hint)
        b.closeButton.setOnClickListener { dismiss() }
        b.searchInput.setOnEditorActionListener { _, id, _ ->
            if (id == EditorInfo.IME_ACTION_SEARCH) { search(b.searchInput.text.toString()); true } else false
        }
        b.searchButton.setOnClickListener { search(b.searchInput.text.toString()) }

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
