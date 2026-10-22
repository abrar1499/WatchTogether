package com.abrar.watchtogether

import android.content.Context
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import androidx.recyclerview.widget.RecyclerView

/**
 * Chat list where each message gets dimmer the older it is:
 * newest 100%, then 92, 81, 70, 50, 30, 15, 10, 5, 3% — anything older is invisible.
 * Messages are never cut; they simply fade out as they rise off the top of the screen.
 * Touches on empty space (or on nearly invisible messages) fall through to the video.
 */
class FadingRecyclerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : RecyclerView(context, attrs) {

    private val levels = floatArrayOf(1f, 0.92f, 0.81f, 0.70f, 0.50f, 0.30f, 0.15f, 0.10f, 0.05f, 0.03f)
    private val slideIn = 18 * resources.displayMetrics.density

    init {
        itemAnimator = null   // we animate ourselves so the opacity steps stay exact
        isVerticalFadingEdgeEnabled = false
    }

    private fun targetAlpha(child: View): Float {
        val pos = getChildAdapterPosition(child)
        val count = adapter?.itemCount ?: 0
        if (pos == NO_POSITION || count == 0) return 0f
        return levels.getOrElse(count - 1 - pos) { 0f }
    }

    private fun applyAlphas() {
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            val target = targetAlpha(child)
            if (child.getTag(R.id.chat_seen) == null) {
                // A brand new message: slide up and fade in
                child.setTag(R.id.chat_seen, true)
                child.alpha = 0f
                child.translationY = slideIn
                child.animate().alpha(target).translationY(0f).setDuration(260).start()
            } else if (child.alpha != target) {
                child.animate().alpha(target).setDuration(260).start()
            }
        }
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        applyAlphas()
    }

    override fun onScrolled(dx: Int, dy: Int) {
        super.onScrolled(dx, dy)
        applyAlphas()
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (ev.actionMasked == MotionEvent.ACTION_DOWN) {
            val child = findChildViewUnder(ev.x, ev.y)
            if (child == null || targetAlpha(child) < 0.3f) return false
        }
        return super.dispatchTouchEvent(ev)
    }
}
