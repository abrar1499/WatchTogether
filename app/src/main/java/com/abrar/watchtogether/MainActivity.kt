package com.abrar.watchtogether

import android.content.Intent
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

class MainActivity : AppCompatActivity() {

    private lateinit var b: ActivityMainBinding
    private lateinit var prefs: Prefs

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        b = ActivityMainBinding.inflate(layoutInflater)
        setContentView(b.root)
        prefs = Prefs(this)
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
            setBusy(true)
            val code = RoomSync.newCode()
            RoomSync.createRoom(code) { ok ->
                setBusy(false)
                if (ok) openRoom(code, name) else toast(tr(R.string.error_network))
            }
        }

        b.codeInput.setOnEditorActionListener { _, id, _ ->
            if (id == EditorInfo.IME_ACTION_GO) { b.joinButton.performClick(); true } else false
        }
        b.joinButton.setOnClickListener {
            val name = readName() ?: return@setOnClickListener
            val code = b.codeInput.text.toString().trim().uppercase()
            if (code.length != 6) {
                b.codeInput.error = tr(R.string.error_code_length)
                return@setOnClickListener
            }
            setBusy(true)
            RoomSync.roomExists(code) { exists ->
                setBusy(false)
                when (exists) {
                    true -> openRoom(code, name)
                    false -> b.codeInput.error = tr(R.string.error_room_not_found)
                    null -> toast(tr(R.string.error_network))
                }
            }
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

    override fun onResume() {
        super.onResume()
        Updater.onMainResumed(this)
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
