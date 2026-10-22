package com.abrar.watchtogether

import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import com.abrar.watchtogether.databinding.ActivityRoomBinding
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.YouTubePlayer
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.listeners.AbstractYouTubePlayerListener
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.options.IFramePlayerOptions
import kotlin.math.abs

class RoomActivity : AppCompatActivity() {

    private lateinit var b: ActivityRoomBinding
    private lateinit var sync: RoomSync
    private lateinit var userId: String
    private val chat = ChatAdapter()

    private var player: YouTubePlayer? = null
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

        b.shareButton.setOnClickListener {
            val text = getString(R.string.share_text, code)
            startActivity(Intent.createChooser(
                Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text),
                getString(R.string.share)
            ))
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
            }
        )
    }

    private fun setupPlayer() {
        lifecycle.addObserver(b.player)
        val options = IFramePlayerOptions.Builder().controls(1).build()
        b.player.initialize(object : AbstractYouTubePlayerListener() {
            override fun onReady(youTubePlayer: YouTubePlayer) {
                player = youTubePlayer
                pendingRemote?.let { applyRemote(it, force = true) }
                pendingRemote = null
            }

            override fun onStateChange(
                youTubePlayer: YouTubePlayer,
                state: PlayerConstants.PlayerState
            ) {
                when (state) {
                    PlayerConstants.PlayerState.PLAYING -> {
                        localPlaying = true
                        lastSecondAt = SystemClock.elapsedRealtime()
                        if (!ignoringLocal() && remote?.playing != true) publish(true, lastSecond)
                    }
                    PlayerConstants.PlayerState.PAUSED -> {
                        localPlaying = false
                        if (!ignoringLocal() && remote?.playing != false) publish(false, lastSecond)
                    }
                    PlayerConstants.PlayerState.ENDED -> localPlaying = false
                    else -> Unit
                }
            }

            override fun onCurrentSecond(youTubePlayer: YouTubePlayer, second: Float) {
                val now = SystemClock.elapsedRealtime()
                // Detect a manual seek: the time jumped more than normal playback explains
                val expected = if (localPlaying) lastSecond + (now - lastSecondAt) / 1000f else lastSecond
                val jumped = lastSecondAt != 0L && abs(second - expected) > SEEK_THRESHOLD
                lastSecond = second
                lastSecondAt = now
                if (jumped && !ignoringLocal()) publish(localPlaying, second)
            }

            override fun onError(youTubePlayer: YouTubePlayer, error: PlayerConstants.PlayerError) {
                toast(getString(R.string.error_video, error.name))
            }
        }, options)
    }

    private fun loadFromInput() {
        val id = YouTubeLink.extractId(b.urlInput.text.toString())
        if (id == null) {
            b.urlInput.error = getString(R.string.error_link)
            return
        }
        b.urlInput.setText("")
        b.urlInput.clearFocus()
        currentVideoId = id
        lastSecond = 0f
        ignoreLocalUntil = SystemClock.elapsedRealtime() + IGNORE_MS
        player?.loadVideo(id, 0f)
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
            if (state.playing) p.loadVideo(state.videoId, target) else p.cueVideo(state.videoId, target)
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
