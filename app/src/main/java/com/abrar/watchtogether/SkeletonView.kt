package com.abrar.watchtogether

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator

/**
 * Placeholder shapes shaped like video results (thumbnail, avatar, two title lines)
 * with a soft shimmer, shown while the real results load.
 */
class SkeletonView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    private val d = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()
    private val shaderMatrix = Matrix()
    private var shader: LinearGradient? = null
    private var shift = 0f

    private val shimmer = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 1200
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener { shift = it.animatedValue as Float; invalidate() }
    }

    // View callbacks can fire during the super constructor, before the animator exists
    private val ready = true

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        shader = LinearGradient(
            0f, 0f, w.toFloat(), 0f,
            intArrayOf(0xFF1C1C20.toInt(), 0xFF2C2C33.toInt(), 0xFF1C1C20.toInt()),
            floatArrayOf(0.3f, 0.5f, 0.7f),
            Shader.TileMode.CLAMP
        )
        paint.shader = shader
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        shaderMatrix.setTranslate((shift * 2f - 1f) * w, 0f)
        shader?.setLocalMatrix(shaderMatrix)

        val pad = 14 * d
        var y = 8 * d
        while (y < height) {
            // Thumbnail
            val thumbH = (w - pad * 2) * 9f / 16f
            rect.set(pad, y, w - pad, y + thumbH)
            canvas.drawRoundRect(rect, 12 * d, 12 * d, paint)
            y += thumbH + 12 * d
            // Channel avatar
            canvas.drawCircle(pad + 18 * d, y + 18 * d, 18 * d, paint)
            // Title lines
            val textX = pad + 48 * d
            rect.set(textX, y + 4 * d, w - pad - 24 * d, y + 16 * d)
            canvas.drawRoundRect(rect, 6 * d, 6 * d, paint)
            rect.set(textX, y + 24 * d, textX + (w - textX - pad) * 0.55f, y + 34 * d)
            canvas.drawRoundRect(rect, 5 * d, 5 * d, paint)
            y += 36 * d + 22 * d
        }
    }

    private fun updateRunning() {
        @Suppress("SENSELESS_COMPARISON")
        if (ready != true) return
        if (isAttachedToWindow && visibility == VISIBLE) {
            if (!shimmer.isStarted) shimmer.start()
        } else {
            shimmer.cancel()
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        updateRunning()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        updateRunning()
    }

    override fun onVisibilityChanged(changedView: View, visibility: Int) {
        super.onVisibilityChanged(changedView, visibility)
        updateRunning()
    }
}
