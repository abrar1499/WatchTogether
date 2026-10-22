package com.abrar.watchtogether

import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.text.InputType
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.SeekBar
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.updatePadding
import androidx.recyclerview.widget.LinearLayoutManager
import com.abrar.watchtogether.databinding.ActivityRoomBinding
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.max

class RoomActivity : AppCompatActivity() {

    private lateinit var b: ActivityRoomBinding
    private lateinit var sync: RoomSync
    private lateinit var userId: String
    private val chat = ChatAdapter()

    private var player: EmbedPlayer? = null
    private var currentVideoId: String? = null
    private var remote: PlaybackState? = null

    // What the local player is doing
    private var localPlaying = false
    private var lastSecond = 0f
    private var lastSecondAt = 0L

    // After we apply a change from the room, ignore the player's own events for a moment
    // so we don't echo the same change back to everyone.
    private var ignoreLocalUntil = 0L

    // Controls & layout
    private var duration = 0f
    private var userSeeking = false
    private lateinit var prefs: Prefs
    private var zoom = 0f   // 0 = whole video, 1 = fills half the screen; set by pinch
    private var fullscreen = false
    private var topInset = 0
    private val hideControls = Runnable { setControlsVisible(false) }
    private val hideChatToast = Runnable { b.chatToast.visibility = View.GONE }
    private val exitFullscreenOnBack = object : OnBackPressedCallback(false) {
        override fun handleOnBackPressed() = setFullscreen(false)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        b = ActivityRoomBinding.inflate(layoutInflater)
        setContentView(b.root)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setupEdgeToEdge()

        val code = intent.getStringExtra(EXTRA_CODE) ?: return finish()
        val name = intent.getStringExtra(EXTRA_NAME) ?: "Guest"
        prefs = Prefs(this)
        userId = prefs.userId
        zoom = prefs.zoom
        sync = RoomSync(code, userId, name)

        b.roomCode.text = code
        b.emptySearchInput.hintR(R.string.search_hint)
        b.messageInput.hintR(R.string.message_hint)
        b.memberCount.text = "1"
        b.chatList.layoutManager = LinearLayoutManager(this).apply { stackFromEnd = true }
        b.chatList.adapter = chat
        chat.myUid = userId

        setupPlayer()
        setupControls()
        SearchWeb.warmUp(this)   // YouTube search is ready before anyone taps it
        updateEmptyState()
        onBackPressedDispatcher.addCallback(this, exitFullscreenOnBack)

        b.backButton.setOnClickListener { finish() }
        b.shareButton.setOnClickListener {
            val text = tr(R.string.share_text, code)
            startActivity(Intent.createChooser(
                Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text),
                tr(R.string.share)
            ))
        }

        b.youtubeButton.setOnClickListener { openSearch(null) }
        b.emptySearchButton.setOnClickListener { openSearch(b.emptySearchInput.text.toString()) }
        b.emptySearchInput.setOnEditorActionListener { _, id, _ ->
            if (id == EditorInfo.IME_ACTION_SEARCH) { openSearch(b.emptySearchInput.text.toString()); true } else false
        }
        b.linkButton.setOnClickListener { askForLink() }

        b.resyncButton.setOnClickListener {
            remote?.let { applyRemote(it, force = true) }
            scheduleHide()
        }

        b.sendButton.setOnClickListener { sendChat() }
        b.messageInput.setOnEditorActionListener { _, id, _ ->
            if (id == EditorInfo.IME_ACTION_SEND) { sendChat(); true } else false
        }

        sync.start(
            onState = { state ->
                remote = state
                // Our own change coming back from the server: nothing to do
                if (state.by == userId && state.videoId == currentVideoId) return@start
                applyRemote(state, force = false)
            },
            onMembers = { members ->
                b.memberCount.text = max(members.size, 1).toString()
                b.memberCount.contentDescription = members.joinToString(", ")
            },
            onMessage = { msg ->
                chat.add(msg)
                b.chatList.scrollToPosition(chat.itemCount - 1)
                if (fullscreen && msg.uid != userId) showChatToast("${msg.name}: ${msg.text}")
            }
        )
    }

    /** Draw behind the status and navigation bars so the video fills the whole phone. */
    private fun setupEdgeToEdge() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }

        ViewCompat.setOnApplyWindowInsetsListener(b.root) { _, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            topInset = bars.top
            // On Android 11+ we move the chat up ourselves when the keyboard opens
            val ime = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                insets.getInsets(WindowInsetsCompat.Type.ime()).bottom else 0
            b.topBar.updatePadding(top = if (fullscreen) dp(6) else bars.top + dp(6))
            b.inputBar.updatePadding(bottom = max(bars.bottom, ime) + dp(12))
            b.chatToast.translationY = bars.top.toFloat()
            insets
        }
    }

    private fun setupPlayer() {
        player = EmbedPlayer(b.player, packageName, object : EmbedPlayer.Listener {
            override fun onState(state: EmbedPlayer.State) {
                updatePlayPauseIcon(state == EmbedPlayer.State.PLAYING ||
                    state == EmbedPlayer.State.BUFFERING)
                when (state) {
                    EmbedPlayer.State.PLAYING -> {
                        b.bufferLoader.visibility = View.GONE
                        hideLoading(delayMs = 300)
                        localPlaying = true
                        scheduleHide()   // after localPlaying is set, or the timer never starts
                        lastSecondAt = SystemClock.elapsedRealtime()
                        if (!ignoringLocal() && remote?.playing != true) publish(true, lastSecond)
                    }
                    EmbedPlayer.State.PAUSED -> {
                        b.bufferLoader.visibility = View.GONE
                        if (!loadingAutoplay) hideLoading(delayMs = 300)
                        setControlsVisible(true, autoHide = false)
                        localPlaying = false
                        if (!ignoringLocal() && remote?.playing != false) publish(false, lastSecond)
                    }
                    EmbedPlayer.State.ENDED -> {
                        b.bufferLoader.visibility = View.GONE
                        hideLoading(delayMs = 0)
                        localPlaying = false
                        setControlsVisible(true, autoHide = false)
                    }
                    EmbedPlayer.State.BUFFERING -> {
                        if (!loading) b.bufferLoader.visibility = View.VISIBLE
                    }
                }
            }

            override fun onTime(second: Float) {
                val now = SystemClock.elapsedRealtime()
                // Detect a manual seek: the time jumped more than normal playback explains
                val expected = if (localPlaying) lastSecond + (now - lastSecondAt) / 1000f else lastSecond
                val jumped = lastSecondAt != 0L && abs(second - expected) > SEEK_THRESHOLD
                lastSecond = second
                lastSecondAt = now
                if (jumped && !ignoringLocal()) publish(localPlaying, second)
                if (!userSeeking) {
                    b.seekBar.progress = second.toInt()
                    updateTimeText(second)
                }
            }

            override fun onDuration(duration: Float) {
                this@RoomActivity.duration = duration
                b.seekBar.max = duration.toInt()
                updateTimeText(lastSecond)
            }

            override fun onVideoArea(fraction: Float) {
                videoFraction = fraction.coerceIn(0.15f, 0.6f)
                if (!fullscreen) setVideoArea(videoFraction)
            }

            override fun onError(message: String) {
                hideLoading(delayMs = 0)
                toast(tr(R.string.error_video))
            }
        })
        player?.setLayout(zoom, full = false)
    }

    override fun onPause() {
        super.onPause()
        player?.onPause()
    }

    override fun onResume() {
        super.onResume()
        player?.onResume()
    }

    // ---------- Controls ----------

    private fun setupControls() {
        // Video area: a tap shows/hides controls.
        // Below the video (or anywhere in full screen): double tap right = +10s, left = -10s.
        val gestures = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent) = true

            override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                if (fullscreen || e.y < videoBottom()) {
                    if (b.controls.visibility == View.VISIBLE) setControlsVisible(false)
                    else setControlsVisible(true)
                }
                return true
            }

            override fun onDoubleTap(e: MotionEvent): Boolean {
                if (!fullscreen && e.y < videoBottom()) return false
                seekBy(if (e.x > b.root.width / 2f) SEEK_STEP else -SEEK_STEP, e.x, e.y)
                return true
            }
        })
        // Pinch on the video: spread to fill (full-screen feel), squeeze to see the whole video
        val pinch = ScaleGestureDetector(this, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(d: ScaleGestureDetector): Boolean {
                if (fullscreen || currentVideoId == null) return false
                setZoom(zoom + (d.scaleFactor - 1f) * 1.6f, save = false)
                return true
            }
            override fun onScaleEnd(d: ScaleGestureDetector) {
                prefs.zoom = zoom
            }
        })
        b.touchShield.setOnTouchListener { v, ev ->
            pinch.onTouchEvent(ev)
            if (!pinch.isInProgress && ev.pointerCount == 1) gestures.onTouchEvent(ev)
            if (ev.actionMasked == MotionEvent.ACTION_UP) v.performClick()
            true
        }
        b.controls.setOnClickListener { setControlsVisible(false) }

        b.playPause.setOnClickListener {
            val p = player ?: return@setOnClickListener
            if (localPlaying) p.pause() else p.play()
            scheduleHide()
        }

        b.seekBar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(bar: SeekBar, progress: Int, fromUser: Boolean) {
                if (fromUser) updateTimeText(progress.toFloat())
            }
            override fun onStartTrackingTouch(bar: SeekBar) {
                userSeeking = true
                b.controls.removeCallbacks(hideControls)
            }
            override fun onStopTrackingTouch(bar: SeekBar) {
                userSeeking = false
                // The jump is picked up in onTime and shared with the room
                player?.seekTo(bar.progress.toFloat())
                scheduleHide()
            }
        })

        // One tap: whole video <-> filled
        b.cropButton.setOnClickListener {
            setZoom(if (zoom < 0.5f) 1f else 0f, save = true)
            scheduleHide()
        }

        b.fullscreenButton.setOnClickListener { setFullscreen(!fullscreen) }
    }

    private fun updateEmptyState() {
        val empty = currentVideoId == null
        b.emptyState.visibility = if (empty) View.VISIBLE else View.GONE
        b.playPause.visibility = if (empty) View.GONE else View.VISIBLE
        b.bottomBar.visibility = if (empty) View.INVISIBLE else View.VISIBLE
        if (empty) setControlsVisible(true, autoHide = false)
    }

    private fun setControlsVisible(visible: Boolean, autoHide: Boolean = true) {
        b.controls.removeCallbacks(hideControls)
        if (visible) {
            if (b.controls.visibility != View.VISIBLE) {
                b.controls.alpha = 0f
                b.controls.visibility = View.VISIBLE
                b.controls.animate().alpha(1f).setDuration(180).start()
            }
            if (autoHide) scheduleHide()
        } else {
            // Keep controls up while paused or before a video is chosen
            if (!localPlaying || currentVideoId == null) return
            b.controls.animate().alpha(0f).setDuration(250)
                .withEndAction { b.controls.visibility = View.GONE }.start()
        }
    }

    private fun scheduleHide() {
        b.controls.removeCallbacks(hideControls)
        if (localPlaying && !userSeeking) b.controls.postDelayed(hideControls, CONTROLS_HIDE_MS)
    }

    private fun setZoom(value: Float, save: Boolean) {
        val z = value.coerceIn(0f, 1f)
        if (z == zoom && !save) return
        zoom = z
        player?.setLayout(zoom, full = fullscreen)
        if (save) prefs.zoom = zoom
    }

    // Where the video ends (as a fraction of screen height); controls and tap zones follow it
    private var videoFraction = 0.5f

    private fun setVideoArea(fraction: Float) {
        val lp = b.mid.layoutParams as ConstraintLayout.LayoutParams
        if (lp.guidePercent == fraction) return
        lp.guidePercent = fraction
        b.mid.layoutParams = lp
    }

    private fun videoBottom(): Float = b.root.height * videoFraction

    // Consecutive double taps on the same side add up: +10s, +20s, +30s…
    private var seekTotal = 0
    private var seekSideRight = true
    private var lastSeekAt = 0L
    private val clearSeekHint = Runnable {
        b.seekHint.animate().alpha(0f).setDuration(200).start()
        seekTotal = 0
    }

    private fun seekBy(seconds: Int, x: Float, y: Float) {
        val p = player ?: return
        if (currentVideoId == null) return
        val now = SystemClock.elapsedRealtime()
        val right = seconds > 0
        seekTotal = if (right == seekSideRight && now - lastSeekAt < 900) seekTotal + seconds else seconds
        seekSideRight = right
        lastSeekAt = now

        val current = if (localPlaying) lastSecond + (now - lastSecondAt) / 1000f else lastSecond
        val max = if (duration > 0f) duration - 1f else Float.MAX_VALUE
        val target = (current + seconds).coerceIn(0f, max)
        lastSecond = target
        lastSecondAt = now
        p.seekTo(target)
        publish(localPlaying, target)   // everyone in the room jumps too

        // Small "+10s" hint where the finger is; no controls
        b.seekHint.text = (if (seekTotal > 0) "+" else "−") + abs(seekTotal) + "s"
        b.seekHint.measure(0, 0)
        b.seekHint.x = (x - b.seekHint.measuredWidth / 2f)
            .coerceIn(dp(12).toFloat(), b.root.width - b.seekHint.measuredWidth - dp(12).toFloat())
        b.seekHint.y = y - b.seekHint.measuredHeight * 2f
        b.seekHint.animate().cancel()
        b.seekHint.alpha = 1f
        b.seekHint.removeCallbacks(clearSeekHint)
        b.seekHint.postDelayed(clearSeekHint, 700)
    }

    private fun updatePlayPauseIcon(playing: Boolean) {
        b.playPause.setImageResource(if (playing) R.drawable.ic_pause else R.drawable.ic_play)
    }

    private fun updateTimeText(second: Float) {
        b.timeText.text = formatTime(second) + " / " + formatTime(duration)
    }

    private fun formatTime(sec: Float): String {
        val t = sec.toInt().coerceAtLeast(0)
        val h = t / 3600
        val m = (t % 3600) / 60
        val s = t % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
    }

    private fun setFullscreen(on: Boolean) {
        if (fullscreen == on) return
        fullscreen = on
        exitFullscreenOnBack.isEnabled = on

        // The video half grows to the whole screen; chat hides
        val mid = b.mid.layoutParams as ConstraintLayout.LayoutParams
        mid.guidePercent = if (on) 1f else videoFraction
        b.mid.layoutParams = mid
        b.chatList.visibility = if (on) View.GONE else View.VISIBLE
        b.inputBar.visibility = if (on) View.GONE else View.VISIBLE
        player?.setLayout(zoom, full = on)

        val insets = WindowCompat.getInsetsController(window, window.decorView)
        if (on) {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            insets.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            insets.hide(WindowInsetsCompat.Type.systemBars())
            b.fullscreenButton.setImageResource(R.drawable.ic_fullscreen_exit)
            b.topBar.updatePadding(top = dp(6))
        } else {
            // Snap back to portrait, then allow rotation again a moment later
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
            b.root.postDelayed({
                if (!fullscreen) requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            }, 2500)
            insets.show(WindowInsetsCompat.Type.systemBars())
            b.fullscreenButton.setImageResource(R.drawable.ic_fullscreen)
            b.chatToast.visibility = View.GONE
            b.topBar.updatePadding(top = topInset + dp(6))
        }
        scheduleHide()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // Turning the phone sideways goes full screen automatically
        if (newConfig.orientation == Configuration.ORIENTATION_LANDSCAPE) setFullscreen(true)
    }

    private fun showChatToast(text: String) {
        b.chatToast.text = text
        b.chatToast.visibility = View.VISIBLE
        b.chatToast.removeCallbacks(hideChatToast)
        b.chatToast.postDelayed(hideChatToast, 4000)
    }

    // ---------- Room actions ----------

    private fun openSearch(query: String?) {
        b.emptySearchInput.clearFocus()
        YouTubeSearchSheet(this, query?.trim()) { id ->
            b.emptySearchInput.setText("")
            playForEveryone(id)
        }.show()
    }

    private fun askForLink() {
        val input = EditText(this).apply {
            hint = tr(R.string.paste_link)
            inputType = InputType.TYPE_TEXT_VARIATION_URI
            isSingleLine = true
        }
        val box = FrameLayout(this).apply {
            setPadding(dp(22), dp(8), dp(22), 0)
            addView(input)
        }
        MaterialAlertDialogBuilder(this)
            .setTitle(tr(R.string.link_dialog_title))
            .setView(box)
            .setPositiveButton(tr(R.string.play)) { _, _ ->
                val id = YouTubeLink.extractId(input.text.toString())
                if (id == null) toast(tr(R.string.error_link)) else playForEveryone(id)
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun playForEveryone(id: String) {
        val p = player
        if (p != null) {
            currentVideoId = id
            lastSecond = 0f
            ignoreLocalUntil = SystemClock.elapsedRealtime() + IGNORE_MS
            showLoading(id, autoplay = true)
            p.load(id, 0f, autoplay = true)
            updateEmptyState()
        }
        sync.pushState(id, true, 0.0)
    }

    private fun publish(playing: Boolean, position: Float) {
        val id = currentVideoId ?: return
        sync.pushState(id, playing, position.toDouble())
    }

    private fun applyRemote(state: PlaybackState, force: Boolean) {
        val p = player ?: return
        ignoreLocalUntil = SystemClock.elapsedRealtime() + IGNORE_MS
        val target = state.positionAt(sync.serverNow()).toFloat()

        if (state.videoId != currentVideoId) {
            currentVideoId = state.videoId
            lastSecond = target
            lastSecondAt = SystemClock.elapsedRealtime()
            showLoading(state.videoId, autoplay = state.playing)
            p.load(state.videoId, target, autoplay = state.playing)
            updateEmptyState()
            return
        }

        val localNow = if (localPlaying)
            lastSecond + (SystemClock.elapsedRealtime() - lastSecondAt) / 1000f
        else lastSecond
        if (force || abs(localNow - target) > DRIFT_THRESHOLD) p.seekTo(target)

        if (state.playing) p.play() else p.pause()
    }

    // ---------- Loading screen ----------

    private var loading = false
    private var loadingAutoplay = true
    private var loadingVideoId: String? = null
    private val hideLoadingNow = Runnable { fadeOutLoading() }

    /** Cover the player with our own loading screen until the new video is really playing. */
    private fun showLoading(videoId: String, autoplay: Boolean) {
        loading = true
        loadingAutoplay = autoplay
        loadingVideoId = videoId
        b.bufferLoader.visibility = View.GONE
        b.loadingOverlay.removeCallbacks(hideLoadingNow)
        b.loadingOverlay.animate().cancel()
        b.loadingOverlay.alpha = 1f
        b.loadingOverlay.visibility = View.VISIBLE
        b.loadingThumb.setImageDrawable(null)
        b.loadingBlur.setImageDrawable(null)
        loadThumbnail(videoId)
        // Never get stuck: give up on the loading screen after 15 seconds
        b.loadingOverlay.postDelayed(hideLoadingNow, 15_000)
    }

    private fun hideLoading(delayMs: Long) {
        if (!loading) return
        b.loadingOverlay.removeCallbacks(hideLoadingNow)
        // A short delay lets the first frames paint before we reveal them
        b.loadingOverlay.postDelayed(hideLoadingNow, delayMs)
    }

    private fun fadeOutLoading() {
        loading = false
        b.loadingOverlay.animate().alpha(0f).setDuration(350)
            .withEndAction { b.loadingOverlay.visibility = View.GONE }.start()
    }

    /** Shows the video's thumbnail on the loading screen (sharp on top, blurred everywhere). */
    private fun loadThumbnail(videoId: String) {
        thread {
            val bmp = listOf("hq720.jpg", "mqdefault.jpg").firstNotNullOfOrNull { name ->
                try {
                    val conn = URL("https://i.ytimg.com/vi/$videoId/$name").openConnection() as HttpURLConnection
                    conn.connectTimeout = 5000
                    conn.readTimeout = 5000
                    if (conn.responseCode == 200) conn.inputStream.use { BitmapFactory.decodeStream(it) } else null
                } catch (e: Exception) {
                    null
                }
            } ?: return@thread
            // A tiny copy stretched over the screen gives a soft, cheap blur on every phone
            val tiny = Bitmap.createScaledBitmap(bmp, 24, 14, true)
            runOnUiThread {
                if (loadingVideoId != videoId || isDestroyed) return@runOnUiThread
                b.loadingThumb.setImageBitmap(bmp)
                b.loadingBlur.setImageBitmap(tiny)
            }
        }
    }

    private fun ignoringLocal() = SystemClock.elapsedRealtime() < ignoreLocalUntil

    private fun sendChat() {
        val text = b.messageInput.text.toString().trim()
        if (text.isEmpty()) return
        sync.sendMessage(text)
        b.messageInput.setText("")
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()

    override fun onDestroy() {
        if (::sync.isInitialized) sync.stop()
        player?.release()
        player = null
        SearchWeb.destroy()
        super.onDestroy()
    }

    companion object {
        const val EXTRA_CODE = "code"
        const val EXTRA_NAME = "name"
        private const val IGNORE_MS = 1500L
        private const val SEEK_THRESHOLD = 2.5f
        private const val DRIFT_THRESHOLD = 1.5f
        private const val CONTROLS_HIDE_MS = 1000L
        private const val SEEK_STEP = 10
    }
}
