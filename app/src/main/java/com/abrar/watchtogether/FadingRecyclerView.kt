package com.abrar.watchtogether

import android.content.Context
import android.util.AttributeSet
import androidx.recyclerview.widget.RecyclerView

/** Fades messages out only at the top edge, so older chat dissolves into the video. */
class FadingRecyclerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : RecyclerView(context, attrs) {

    override fun getTopFadingEdgeStrength(): Float = 1f
    override fun getBottomFadingEdgeStrength(): Float = 0f
}
