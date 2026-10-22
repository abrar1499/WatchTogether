package com.abrar.watchtogether

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.core.content.FileProvider
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.progressindicator.LinearProgressIndicator
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Checks GitHub Releases for a newer build (tag "v<number>") and offers to install it.
 * Each CI build publishes a release whose number equals the app's versionCode.
 */
object Updater {

    private const val LATEST_URL =
        "https://api.github.com/repos/abrar1499/WatchTogether/releases/latest"

    private val main = Handler(Looper.getMainLooper())
    private var checkedThisSession = false

    fun checkOnStart(activity: Activity) {
        if (checkedThisSession) return
        checkedThisSession = true
        check(activity, silent = true)
    }

    fun check(activity: Activity, silent: Boolean) {
        thread {
            val release = try { fetchLatest() } catch (e: Exception) { null }
            main.post {
                if (activity.isFinishing || activity.isDestroyed) return@post
                when {
                    release == null -> if (!silent) toast(activity, R.string.update_check_failed)
                    release.version > BuildConfig.VERSION_CODE -> offer(activity, release)
                    else -> if (!silent) toast(activity, R.string.update_none)
                }
            }
        }
    }

    private data class Release(val version: Int, val apkUrl: String, val notes: String)

    private fun fetchLatest(): Release? {
        val conn = URL(LATEST_URL).openConnection() as HttpURLConnection
        conn.setRequestProperty("Accept", "application/vnd.github+json")
        conn.connectTimeout = 10_000
        conn.readTimeout = 10_000
        try {
            if (conn.responseCode != 200) return null
            val json = JSONObject(conn.inputStream.bufferedReader().readText())
            val version = json.optString("tag_name").removePrefix("v").toIntOrNull() ?: return null
            val assets = json.optJSONArray("assets") ?: return null
            for (i in 0 until assets.length()) {
                val a = assets.getJSONObject(i)
                if (a.optString("name").endsWith(".apk")) {
                    return Release(version, a.getString("browser_download_url"), json.optString("body"))
                }
            }
            return null
        } finally {
            conn.disconnect()
        }
    }

    private fun offer(activity: Activity, release: Release) {
        MaterialAlertDialogBuilder(activity)
            .setTitle(activity.getString(R.string.update_title, release.version))
            .setMessage(R.string.update_message)
            .setPositiveButton(R.string.update_now) { _, _ -> download(activity, release) }
            .setNegativeButton(R.string.update_later, null)
            .show()
    }

    private fun download(activity: Activity, release: Release) {
        val bar = LinearProgressIndicator(activity).apply {
            isIndeterminate = true
            val pad = (24 * activity.resources.displayMetrics.density).toInt()
            setPadding(pad, pad / 2, pad, pad / 2)
        }
        val dialog: AlertDialog = MaterialAlertDialogBuilder(activity)
            .setTitle(R.string.update_downloading)
            .setView(bar)
            .setCancelable(false)
            .show()

        thread {
            val file = File(activity.getExternalFilesDir("updates"), "update.apk")
            val ok = try {
                file.parentFile?.mkdirs()
                val conn = URL(release.apkUrl).openConnection() as HttpURLConnection
                conn.instanceFollowRedirects = true
                conn.connectTimeout = 15_000
                conn.readTimeout = 30_000
                val total = conn.contentLengthLong
                conn.inputStream.use { input ->
                    file.outputStream().use { out ->
                        val buf = ByteArray(64 * 1024)
                        var done = 0L
                        var lastPct = -1
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            out.write(buf, 0, n)
                            done += n
                            if (total > 0) {
                                val pct = (done * 100 / total).toInt()
                                if (pct != lastPct) main.post {
                                    bar.isIndeterminate = false
                                    bar.setProgressCompat(pct, true)
                                }
                                lastPct = pct
                            }
                        }
                    }
                }
                conn.disconnect()
                file.length() > 0
            } catch (e: Exception) {
                false
            }
            main.post {
                dialog.dismiss()
                if (activity.isFinishing || activity.isDestroyed) return@post
                if (ok) install(activity, file) else toast(activity, R.string.update_download_failed)
            }
        }
    }

    private fun install(activity: Activity, file: File) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            // One-time permission: "Install unknown apps" for this app
            toast(activity, R.string.update_allow_install)
            activity.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + activity.packageName)
                )
            )
            pendingFile = file
            return
        }
        val uri = FileProvider.getUriForFile(activity, activity.packageName + ".files", file)
        activity.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    // If we had to send the user to settings first, finish the install when they come back
    private var pendingFile: File? = null

    fun resumePendingInstall(activity: Activity) {
        val file = pendingFile ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) return
        pendingFile = null
        install(activity, file)
    }

    private fun toast(activity: Activity, res: Int) =
        Toast.makeText(activity, res, Toast.LENGTH_LONG).show()
}
