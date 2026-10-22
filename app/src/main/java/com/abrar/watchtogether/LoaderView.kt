package com.abrar.watchtogether

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.SweepGradient
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator
import kotlin.math.min

/**
 * Loading animation: a glowing gradient ring spinning.
 */
class LoaderView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    private val density = resources.displayMetrics.density
    private val stroke = 4f * density

    private val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = stroke
        color = Color.argb(38, 255, 255, 255)
    }
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = stroke
        strokeCap = Paint.Cap.ROUND
    }
    private val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = stroke * 3.5f
        strokeCap = Paint.Cap.ROUND
        alpha = 70
    }
    private val disc = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(70, 0, 0, 0) }
    private val play = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    private val oval = RectF()
    private val triangle = Path()

    private var angle = 0f
    private var pulse = 1f

    private val spin = ValueAnimator.ofFloat(0f, 360f).apply {
        duration = 1100
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener { angle = it.animatedValue as Float; invalidate() }
    }
    private val beat = ValueAnimator.ofFloat(0.82f, 1f).apply {
        duration = 650
        repeatCount = ValueAnimator.INFINITE
        repeatMode = ValueAnimator.REVERSE
        addUpdateListener { pulse = it.animatedValue as Float }
    }

    // View callbacks can fire during the super constructor, before the animators exist
    private val ready = true

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        val cx = w / 2f
        val cy = h / 2f
        val r = min(w, h) / 2f - stroke * 2.5f
        oval.set(cx - r, cy - r, cx + r, cy + r)
        // Tail fades to transparent, head is bright pink
        val shader = SweepGradient(
            cx, cy,
            intArrayOf(Color.TRANSPARENT, 0xFFE5484D.toInt(), 0xFFFFB3B6.toInt()),
            floatArrayOf(0f, 0.55f, 0.78f)
        )
        ring.shader = shader
        glow.shader = shader
    }

    override fun onDraw(canvas: Canvas) {
        val cx = width / 2f
        val cy = height / 2f
        val r = oval.width() / 2f

        canvas.drawCircle(cx, cy, r, track)

        canvas.save()
        canvas.rotate(angle, cx, cy)
        canvas.drawArc(oval, 0f, 280f, false, glow)
        canvas.drawArc(oval, 0f, 280f, false, ring)
        canvas.restore()

    }

    private fun updateRunning() {
        @Suppress("SENSELESS_COMPARISON")
        if (ready != true) return
        val run = isAttachedToWindow && visibility == VISIBLE && windowVisibility == VISIBLE
        if (run) {
            if (!spin.isStarted) spin.start()
            if (!beat.isStarted) beat.start()
        } else {
            spin.cancel()
            beat.cancel()
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

    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        updateRunning()
    }
}
