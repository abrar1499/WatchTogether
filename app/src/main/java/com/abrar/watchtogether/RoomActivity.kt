package com.abrar.watchtogether

import android.app.Activity
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.SeekBar
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.recyclerview.widget.LinearLayoutManager
import com.abrar.watchtogether.databinding.ActivityRoomBinding
import kotlin.math.abs
import kotlin.math.max

class RoomActivity : AppCompatActivity() {

    private lateinit var b: ActivityRoomBinding
    private lateinit var sync: RoomSync
    private lateinit var userId: String
    private val chat = ChatAdapter()

    private val pickVideo = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val id = result.data?.getStringExtra(YouTubeBrowseActivity.EXTRA_VIDEO_ID)
        if (result.resultCode == Activity.RESULT_OK && id != null) playForEveryone(id)
    }

    private var player: EmbedPlayer? = null
    private var currentVideoId: String? = null
    private var remote: PlaybackState? = null
    private var pendingRemote: PlaybackState? = null

    // What the local player is doing
    private var localPlaying = false
    private var lastSecond = 0f
    private var lastSecondAt = 0L

    // After we apply a change from the room, ignore the player's own events for a moment
    // so we don't echo the same change back to everyone.
    private var ignoreLocalUntil = 0L

    // Custom controls
    private var duration = 0f
    private var userSeeking = false
    private var fillMode = true
    private var fullscreen = false
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

        val code = intent.getStringExtra(EXTRA_CODE) ?: return finish()
        val name = intent.getStringExtra(EXTRA_NAME) ?: "Guest"
        userId = Prefs(this).userId
        sync = RoomSync(code, userId, name)

        b.roomCode.text = getString(R.string.room_code_label, code)
        b.chatList.layoutManager = LinearLayoutManager(this).apply { stackFromEnd = true }
        b.chatList.adapter = chat
        chat.myUid = userId

        setupPlayer()
        setupControls()
        onBackPressedDispatcher.addCallback(this, exitFullscreenOnBack)

        b.shareButton.setOnClickListener {
            val text = getString(R.string.share_text, code)
            startActivity(Intent.createChooser(
                Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text),
                getString(R.string.share)
            ))
        }

        b.youtubeButton.setOnClickListener {
            pickVideo.launch(Intent(this, YouTubeBrowseActivity::class.java))
        }
        b.loadButton.setOnClickListener { loadFromInput() }
        b.urlInput.setOnEditorActionListener { _, id, _ ->
            if (id == EditorInfo.IME_ACTION_GO) { loadFromInput(); true } else false
        }

        b.resyncButton.setOnClickListener {
            remote?.let { applyRemote(it, force = true) }
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
                b.memberCount.text = resources.getQuantityString(
                    R.plurals.watching_count, members.size, members.size
                )
                b.memberCount.contentDescription = members.joinToString(", ")
            },
            onMessage = { msg ->
                chat.add(msg)
                b.chatList.scrollToPosition(chat.itemCount - 1)
                if (fullscreen && msg.uid != userId) showChatToast("${msg.name}: ${msg.text}")
            }
        )
    }

    private fun setupPlayer() {
        player = EmbedPlayer(b.player, packageName, object : EmbedPlayer.Listener {
            override fun onState(state: EmbedPlayer.State) {
                updatePlayPauseIcon(state == EmbedPlayer.State.PLAYING ||
                    state == EmbedPlayer.State.BUFFERING)
                when (state) {
                    EmbedPlayer.State.PLAYING -> {
                        scheduleHide()
                        localPlaying = true
                        lastSecondAt = SystemClock.elapsedRealtime()
                        if (!ignoringLocal() && remote?.playing != true) publish(true, lastSecond)
                    }
                    EmbedPlayer.State.PAUSED -> {
                        setControlsVisible(true, autoHide = false)
                        localPlaying = false
                        if (!ignoringLocal() && remote?.playing != false) publish(false, lastSecond)
                    }
                    EmbedPlayer.State.ENDED -> {
                        localPlaying = false
                        setControlsVisible(true, autoHide = false)
                    }
                    EmbedPlayer.State.BUFFERING -> Unit
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

            override fun onError(message: String) {
                toast(getString(R.string.error_video, message.ifBlank { "?" }))
            }
        })
    }

    override fun onPause() {
        super.onPause()
        player?.onPause()
    }

    override fun onResume() {
        super.onResume()
        player?.onResume()
    }

    // ---------- Custom player controls ----------

    private fun setupControls() {
        b.touchShield.setOnClickListener { setControlsVisible(true) }
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
                // The jump is picked up in onCurrentSecond and shared with the room
                player?.seekTo(bar.progress.toFloat())
                scheduleHide()
            }
        })

        b.cropButton.setOnClickListener {
            fillMode = !fillMode
            applyVideoScale()
            toast(getString(if (fillMode) R.string.crop_fill else R.string.crop_fit))
            scheduleHide()
        }

        b.fullscreenButton.setOnClickListener { setFullscreen(!fullscreen) }

        b.playerBox.addOnLayoutChangeListener { _, l, t, r, bottom, ol, ot, or, ob ->
            if (r - l != or - ol || bottom - t != ob - ot) applyVideoScale()
        }
    }

    /** Zooms the player so the video covers the whole box (cropping the edges). */
    private fun applyVideoScale() {
        val w = b.playerBox.width.toFloat()
        val h = b.playerBox.height.toFloat()
        if (w <= 0f || h <= 0f) return
        val video = 16f / 9f
        val box = w / h
        val cover = max(box / video, video / box)
        val scale = if (fillMode) max(cover, MIN_FILL_ZOOM) else 1f
        b.player.scaleX = scale
        b.player.scaleY = scale
    }

    private fun setControlsVisible(visible: Boolean, autoHide: Boolean = true) {
        b.controls.removeCallbacks(hideControls)
        if (visible) {
            if (b.controls.visibility != View.VISIBLE) {
                b.controls.alpha = 0f
                b.controls.visibility = View.VISIBLE
                b.controls.animate().alpha(1f).setDuration(150).start()
            }
            if (autoHide) scheduleHide()
        } else {
            if (!localPlaying) return   // keep controls up while paused
            b.controls.animate().alpha(0f).setDuration(200)
                .withEndAction { b.controls.visibility = View.GONE }.start()
        }
    }

    private fun scheduleHide() {
        b.controls.removeCallbacks(hideControls)
        if (localPlaying && !userSeeking) b.controls.postDelayed(hideControls, 3000)
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

        val lp = b.playerBox.layoutParams as ConstraintLayout.LayoutParams
        val insets = WindowCompat.getInsetsController(window, window.decorView)
        if (on) {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            b.content.visibility = View.GONE
            lp.dimensionRatio = null
            lp.bottomToBottom = ConstraintLayout.LayoutParams.PARENT_ID
            insets.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            insets.hide(WindowInsetsCompat.Type.systemBars())
            b.fullscreenButton.setImageResource(R.drawable.ic_fullscreen_exit)
        } else {
            // Snap back to portrait, then allow rotation again a moment later
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
            b.playerBox.postDelayed({
                if (!fullscreen) requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            }, 2500)
            b.content.visibility = View.VISIBLE
            lp.dimensionRatio = "H,16:9"
            lp.bottomToBottom = ConstraintLayout.LayoutParams.UNSET
            insets.show(WindowInsetsCompat.Type.systemBars())
            b.fullscreenButton.setImageResource(R.drawable.ic_fullscreen)
            b.chatToast.visibility = View.GONE
        }
        b.playerBox.layoutParams = lp
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

    private fun loadFromInput() {
        val id = YouTubeLink.extractId(b.urlInput.text.toString())
        if (id == null) {
            b.urlInput.error = getString(R.string.error_link)
            return
        }
        b.urlInput.setText("")
        b.urlInput.clearFocus()
        playForEveryone(id)
    }

    private fun playForEveryone(id: String) {
        val p = player
        if (p != null) {
            currentVideoId = id
            lastSecond = 0f
            ignoreLocalUntil = SystemClock.elapsedRealtime() + IGNORE_MS
            p.load(id, 0f, autoplay = true)
        }
        // If the player isn't ready yet, the room update will load it once it is
        sync.pushState(id, true, 0.0)
    }

    private fun publish(playing: Boolean, position: Float) {
        val id = currentVideoId ?: return
        sync.pushState(id, playing, position.toDouble())
    }

    private fun applyRemote(state: PlaybackState, force: Boolean) {
        val p = player
        if (p == null) {
            pendingRemote = state
            return
        }
        ignoreLocalUntil = SystemClock.elapsedRealtime() + IGNORE_MS
        val target = state.positionAt(sync.serverNow()).toFloat()

        if (state.videoId != currentVideoId) {
            currentVideoId = state.videoId
            lastSecond = target
            lastSecondAt = SystemClock.elapsedRealtime()
            p.load(state.videoId, target, autoplay = state.playing)
            return
        }

        val localNow = if (localPlaying)
            lastSecond + (SystemClock.elapsedRealtime() - lastSecondAt) / 1000f
        else lastSecond
        if (force || abs(localNow - target) > DRIFT_THRESHOLD) p.seekTo(target)

        if (state.playing) p.play() else p.pause()
    }

    private fun ignoringLocal() = SystemClock.elapsedRealtime() < ignoreLocalUntil

    private fun sendChat() {
        val text = b.messageInput.text.toString().trim()
        if (text.isEmpty()) return
        sync.sendMessage(text)
        b.messageInput.setText("")
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()

    override fun onDestroy() {
        if (::sync.isInitialized) sync.stop()
        player?.release()
        player = null
        super.onDestroy()
    }

    companion object {
        const val EXTRA_CODE = "code"
        const val EXTRA_NAME = "name"
        private const val IGNORE_MS = 1500L
        private const val SEEK_THRESHOLD = 2.5f
        private const val DRIFT_THRESHOLD = 1.5f
        // Slight zoom even in a 16:9 box so YouTube's edge branding is cropped away
        private const val MIN_FILL_ZOOM = 1.12f
    }
}
