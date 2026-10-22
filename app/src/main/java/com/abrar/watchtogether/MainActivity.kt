package com.abrar.watchtogether

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.abrar.watchtogether.databinding.ActivityMainBinding

class MainActivity : AppCompatActivity() {

    private lateinit var b: ActivityMainBinding
    private lateinit var prefs: Prefs

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        b = ActivityMainBinding.inflate(layoutInflater)
        setContentView(b.root)
        prefs = Prefs(this)

        b.nameInput.setText(prefs.name)
        b.versionText.text = getString(R.string.version_label, BuildConfig.VERSION_NAME)
        b.versionText.setOnClickListener { Updater.check(this, silent = false) }
        Updater.checkOnStart(this)
        b.setupWarning.visibility =
            if (WatchApp.isFirebaseConfigured()) View.GONE else View.VISIBLE

        b.createButton.setOnClickListener {
            val name = readName() ?: return@setOnClickListener
            setBusy(true)
            val code = RoomSync.newCode()
            RoomSync.createRoom(code) { ok ->
                setBusy(false)
                if (ok) openRoom(code, name) else toast(getString(R.string.error_network))
            }
        }

        b.joinButton.setOnClickListener {
            val name = readName() ?: return@setOnClickListener
            val code = b.codeInput.text.toString().trim().uppercase()
            if (code.length != 6) {
                b.codeInput.error = getString(R.string.error_code_length)
                return@setOnClickListener
            }
            setBusy(true)
            RoomSync.roomExists(code) { exists ->
                setBusy(false)
                when (exists) {
                    true -> openRoom(code, name)
                    false -> b.codeInput.error = getString(R.string.error_room_not_found)
                    null -> toast(getString(R.string.error_network))
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        Updater.resumePendingInstall(this)
    }

    private fun readName(): String? {
        if (!WatchApp.isFirebaseConfigured()) {
            toast(getString(R.string.setup_needed))
            return null
        }
        val name = b.nameInput.text.toString().trim()
        if (name.isEmpty()) {
            b.nameInput.error = getString(R.string.error_name)
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
        b.progress.visibility = if (busy) View.VISIBLE else View.GONE
        b.createButton.isEnabled = !busy
        b.joinButton.isEnabled = !busy
    }

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
}
