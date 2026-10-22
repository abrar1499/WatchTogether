package com.abrar.watchtogether

import android.app.Activity
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.text.InputType
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.SeekBar
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
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
    private var fillMode = true
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
        userId = Prefs(this).userId
        sync = RoomSync(code, userId, name)

        b.roomCode.text = code
        b.memberCount.text = "1"
        b.chatList.layoutManager = LinearLayoutManager(this).apply { stackFromEnd = true }
        b.chatList.adapter = chat
        chat.myUid = userId

        setupPlayer()
        setupControls()
        updateEmptyState()
        onBackPressedDispatcher.addCallback(this, exitFullscreenOnBack)

        b.backButton.setOnClickListener { finish() }
        b.shareButton.setOnClickListener {
            val text = getString(R.string.share_text, code)
            startActivity(Intent.createChooser(
                Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text),
                getString(R.string.share)
            ))
        }

        val openPicker = View.OnClickListener {
            pickVideo.launch(Intent(this, YouTubeBrowseActivity::class.java))
        }
        b.youtubeButton.setOnClickListener(openPicker)
        b.emptyPickButton.setOnClickListener(openPicker)
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
            // Chat may rise over the video, but stays below the top buttons
            (b.chatList.layoutParams as ViewGroup.MarginLayoutParams).topMargin = bars.top + dp(58)
            b.chatList.requestLayout()
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
        player?.setLayout(fit = !fillMode, full = false)
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
        b.touchShield.setOnClickListener {
            if (b.controls.visibility == View.VISIBLE) setControlsVisible(false)
            else setControlsVisible(true)
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

        b.cropButton.setOnClickListener {
            fillMode = !fillMode
            player?.setLayout(fit = !fillMode, full = fullscreen)
            toast(getString(if (fillMode) R.string.crop_fill else R.string.crop_fit))
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

        // The video half grows to the whole screen; chat hides
        val mid = b.mid.layoutParams as ConstraintLayout.LayoutParams
        mid.guidePercent = if (on) 1f else 0.5f
        b.mid.layoutParams = mid
        b.chatList.visibility = if (on) View.GONE else View.VISIBLE
        b.inputBar.visibility = if (on) View.GONE else View.VISIBLE
        player?.setLayout(fit = !fillMode, full = on)

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

    private fun askForLink() {
        val input = EditText(this).apply {
            hint = getString(R.string.paste_link)
            inputType = InputType.TYPE_TEXT_VARIATION_URI
            isSingleLine = true
        }
        val box = FrameLayout(this).apply {
            setPadding(dp(22), dp(8), dp(22), 0)
            addView(input)
        }
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.link_dialog_title)
            .setView(box)
            .setPositiveButton(R.string.play) { _, _ ->
                val id = YouTubeLink.extractId(input.text.toString())
                if (id == null) toast(getString(R.string.error_link)) else playForEveryone(id)
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
        super.onDestroy()
    }

    companion object {
        const val EXTRA_CODE = "code"
        const val EXTRA_NAME = "name"
        private const val IGNORE_MS = 1500L
        private const val SEEK_THRESHOLD = 2.5f
        private const val DRIFT_THRESHOLD = 1.5f
    }
}
