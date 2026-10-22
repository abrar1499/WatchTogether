package com.abrar.watchtogether

import android.content.Context
import android.util.AttributeSet
import android.view.MotionEvent
import androidx.recyclerview.widget.RecyclerView

/**
 * Fades messages out only at the top edge, so older chat dissolves into the video.
 * Touches on empty space fall through to the video below (to show the controls).
 */
class FadingRecyclerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : RecyclerView(context, attrs) {

    override fun getTopFadingEdgeStrength(): Float = 1f
    override fun getBottomFadingEdgeStrength(): Float = 0f

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (ev.actionMasked == MotionEvent.ACTION_DOWN && findChildViewUnder(ev.x, ev.y) == null) {
            return false
        }
        return super.dispatchTouchEvent(ev)
    }
}
