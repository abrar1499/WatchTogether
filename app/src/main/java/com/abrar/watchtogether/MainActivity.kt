package com.abrar.watchtogether

import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import com.abrar.watchtogether.databinding.ActivityMainBinding
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import com.google.firebase.database.DatabaseReference
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ValueEventListener

class MainActivity : AppCompatActivity() {

    private lateinit var b: ActivityMainBinding
    private lateinit var prefs: Prefs
    private var liveUiRef: DatabaseReference? = null
    private var liveUiListener: ValueEventListener? = null
    private var pendingInviteCode: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        b = ActivityMainBinding.inflate(layoutInflater)
        setContentView(b.root)
        prefs = Prefs(this)
        pendingInviteCode = roomCodeFromIntent(intent)
        edgeToEdge()

        // Labels can be changed from the remote settings file
        b.titleText.textR(R.string.app_name)
        b.setupWarning.textR(R.string.setup_needed)
        b.nameInput.hintR(R.string.your_name)
        b.createButton.textR(R.string.create_room)
        b.orText.textR(R.string.or_join)
        b.codeInput.hintR(R.string.room_code)
        b.joinButton.textR(R.string.join_room)

        b.nameInput.setText(prefs.name)
        b.versionText.text = tr(R.string.version_label, BuildConfig.VERSION_NAME)
        b.versionText.setOnClickListener { Updater.check(this, manual = true) }
        Updater.checkOnStart(this)
        b.setupWarning.visibility =
            if (WatchApp.isFirebaseConfigured()) View.GONE else View.VISIBLE

        b.createButton.setOnClickListener {
            val name = readName() ?: return@setOnClickListener
            val invite = pendingInviteCode
            if (invite != null) {
                joinRoom(invite, name)
                return@setOnClickListener
            }
            setBusy(true)
            val code = RoomSync.newCode()
            RoomSync.createRoom(code) { ok ->
                setBusy(false)
                if (ok) openRoom(code, name) else toast(tr(R.string.error_network))
            }
        }

        // Opening an invite link joins immediately when this phone already has a saved name.
        // First-time users only need to enter their name; the room code stays inside the link.
        pendingInviteCode?.let { code ->
            b.createButton.text = tr(R.string.join_room)
            val savedName = prefs.name.trim()
            if (savedName.isNotEmpty()) b.root.post { joinRoom(code, savedName) }
        }
    }

    /** Background runs behind the status and navigation bars. */
    private fun edgeToEdge() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }
        ViewCompat.setOnApplyWindowInsetsListener(b.root) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.ime())
            v.setPadding(0, bars.top, 0, bars.bottom)
            insets
        }
    }

    override fun onStart() {
        super.onStart()
        // Read-only live UI updates; the Firebase path is controlled by database rules.
        if (!WatchApp.isFirebaseConfigured() || liveUiListener != null) return
        try {
            val ref = FirebaseDatabase.getInstance().getReference("appConfig/live")
            val listener = object : ValueEventListener {
                override fun onDataChange(snapshot: DataSnapshot) {
                    // Defaults remain intact if the config is absent or malformed.
                    val texts = snapshot.child("texts")
                    fun label(key: String, fallback: Int): String {
                        val value = texts.child(key).getValue(String::class.java)?.trim()
                        return value?.takeIf { it.isNotEmpty() && it.length <= 80 } ?: tr(fallback)
                    }
                    b.titleText.text = label("app_name", R.string.app_name)
                    b.createButton.text = if (pendingInviteCode != null) tr(R.string.join_room) else label("create_room", R.string.create_room)
                    b.joinButton.text = label("join_room", R.string.join_room)

                    val color = snapshot.child("theme/primaryColor")
                        .getValue(String::class.java)
                    val parsedColor = color?.takeIf {
                        Regex("^#[0-9a-fA-F]{6}$").matches(it)
                    }?.let { runCatching { Color.parseColor(it) }.getOrNull() }
                    b.createButton.backgroundTintList = ColorStateList.valueOf(
                        parsedColor ?: androidx.core.content.ContextCompat.getColor(
                            this@MainActivity, R.color.accent
                        )
                    )
                }

                override fun onCancelled(error: DatabaseError) {
                    // Keep the existing UI when access is denied or offline.
                }
            }
            ref.addValueEventListener(listener)
            liveUiRef = ref
            liveUiListener = listener
        } catch (_: Exception) {
            // Firebase might not be initialized on an unconfigured installation.
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val code = roomCodeFromIntent(intent) ?: return
        pendingInviteCode = code
        b.createButton.text = tr(R.string.join_room)
        val savedName = prefs.name.trim().ifEmpty { b.nameInput.text.toString().trim() }
        if (savedName.isNotEmpty()) {
            b.nameInput.setText(savedName)
            joinRoom(code, savedName)
        }
    }

    override fun onStop() {
        liveUiListener?.let { listener -> liveUiRef?.removeEventListener(listener) }
        liveUiListener = null
        liveUiRef = null
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        Updater.onMainResumed(this)
    }

    private fun joinRoom(code: String, name: String) {
        if (!WatchApp.isFirebaseConfigured()) {
            toast(tr(R.string.setup_needed))
            return
        }
        setBusy(true)
        RoomSync.roomExists(code) { exists ->
            setBusy(false)
            when (exists) {
                true -> {
                    openRoom(code, name)
                    if (pendingInviteCode == code) finish()
                }
                false -> {
                    toast(tr(R.string.error_room_not_found))
                    if (pendingInviteCode == code) {
                        pendingInviteCode = null
                        b.createButton.text = tr(R.string.create_room)
                    }
                }
                null -> toast(tr(R.string.error_network))
            }
        }
    }

    private fun roomCodeFromIntent(intent: Intent?): String? {
        val uri = intent?.data ?: return null
        if (uri.scheme != "watchtogether" || uri.host != "room") return null
        val code = uri.lastPathSegment?.uppercase() ?: return null
        return code.takeIf { Regex("[A-HJ-NP-Z2-9]{6}").matches(it) }
    }

    private fun readName(): String? {
        if (!WatchApp.isFirebaseConfigured()) {
            toast(tr(R.string.setup_needed))
            return null
        }
        val name = b.nameInput.text.toString().trim()
        if (name.isEmpty()) {
            b.nameInput.error = tr(R.string.error_name)
            return null
        }
        prefs.name = name
        return name
    }

    private fun openRoom(code: String, name: String) {
        startActivity(
            Intent(this, RoomActivity::class.java)
                .putExtra(RoomActivity.EXTRA_CODE, code)
                .putExtra(RoomActivity.EXTRA_NAME, name)
        )
    }

    private fun setBusy(busy: Boolean) {
        b.progress.visibility = if (busy) View.VISIBLE else View.INVISIBLE
        b.createButton.isEnabled = !busy
        b.joinButton.isEnabled = !busy
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
}
