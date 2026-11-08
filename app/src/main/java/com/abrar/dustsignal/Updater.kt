package com.abrar.dustsignal

import android.app.Activity
import android.app.AlertDialog
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.widget.Toast
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Keeps the app up to date from GitHub Releases (tag "v<number>" = versionCode).
 *
 * A newer APK downloads quietly in the background. Then the player is asked
 * "Update now / Later", so an update never interrupts a mission without asking.
 */
object Updater {

    private const val LATEST_URL =
        "https://api.github.com/repos/abrar1499/WatchTogether/releases/latest"

    private val main = Handler(Looper.getMainLooper())
    private var lastCheck = 0L
    private var checking = false
    private var resumed = false
    private var asking = false
    private var waitingForPermission = false

    private var readyFile: File? = null
    private var readyVersion = 0
    private var lastFile: File? = null

    private data class Release(val version: Int, val apkUrl: String)

    fun checkOnStart(activity: Activity) = check(activity, manual = false)

    /**
     * Looks for a newer release. Automatic checks run at most every 5 minutes (on start and
     * whenever the game comes back to the front); a manual check always runs and reports back.
     */
    fun check(activity: Activity, manual: Boolean) {
        val now = System.currentTimeMillis()
        if (checking) return
        if (!manual && now - lastCheck < 5 * 60 * 1000) return
        if (readyFile != null) { if (manual) ask(activity); return }
        lastCheck = now
        checking = true
        val app = activity.applicationContext
        if (manual) toast(app, R.string.update_checking)
        thread {
            val release = try { fetchLatest() } catch (e: Exception) { null }
            if (release == null) { checking = false; if (manual) main.post { toast(app, R.string.update_check_failed) }; return@thread }
            if (release.version <= currentVersion(app)) { checking = false; if (manual) main.post { toast(app, R.string.update_none) }; return@thread }
            if (manual) main.post { toast(app, R.string.update_downloading) }
            val file = File(app.getExternalFilesDir("updates"), "update-${release.version}.apk")
            val ok = file.length() > 0 || download(release.apkUrl, file)
            checking = false
            if (!ok) { if (manual) main.post { toast(app, R.string.update_download_failed) }; return@thread }
            main.post {
                readyFile = file
                readyVersion = release.version
                if (resumed && !activity.isFinishing) ask(activity)
            }
        }
    }

    fun versionName(context: Context): String = try {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: ""
    } catch (e: Exception) { "" }

    private fun toast(context: Context, res: Int) = Toast.makeText(context, res, Toast.LENGTH_LONG).show()

    fun onResumed(activity: Activity) {
        resumed = true
        if (readyFile == null) { check(activity, manual = false); return }
        if (waitingForPermission) {
            if (!canInstall(activity)) return
            waitingForPermission = false
            install(activity)
            return
        }
        ask(activity)
    }

    fun onPaused() {
        resumed = false
    }

    private fun ask(activity: Activity) {
        if (asking || readyFile == null) return
        asking = true
        AlertDialog.Builder(activity)
            .setTitle(activity.getString(R.string.update_title, readyVersion))
            .setMessage(R.string.update_message)
            .setPositiveButton(R.string.update_now) { _, _ -> asking = false; install(activity) }
            .setNegativeButton(R.string.update_later) { _, _ -> asking = false; readyFile = null }
            .setOnCancelListener { asking = false; readyFile = null }
            .show()
    }

    private fun canInstall(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()

    private fun install(activity: Activity) {
        val file = readyFile ?: return
        if (!canInstall(activity)) {
            waitingForPermission = true
            AlertDialog.Builder(activity)
                .setTitle(R.string.update_permission_title)
                .setMessage(R.string.update_permission_message)
                .setPositiveButton(R.string.update_permission_ok) { _, _ ->
                    activity.startActivity(
                        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + activity.packageName))
                    )
                }
                .setNegativeButton(R.string.update_later) { _, _ -> waitingForPermission = false; readyFile = null }
                .show()
            return
        }
        readyFile = null
        Toast.makeText(activity, R.string.update_installing, Toast.LENGTH_LONG).show()
        try {
            sessionInstall(activity.applicationContext, file)
        } catch (e: Exception) {
            manualInstall(activity.applicationContext, file)
        }
    }

    /** Installs through PackageInstaller; on Android 12+ this can finish without any tap. */
    private fun sessionInstall(context: Context, file: File) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(context.packageName)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            session.openWrite("base.apk", 0, file.length()).use { out ->
                file.inputStream().use { it.copyTo(out) }
                session.fsync(out)
            }
            lastFile = file
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            val callback = PendingIntent.getBroadcast(
                context, sessionId, Intent(context, InstallReceiver::class.java), flags
            )
            session.commit(callback.intentSender)
        }
    }

    /** Android's normal install screen, used when the quiet install is not possible. */
    fun manualInstall(context: Context, file: File? = lastFile) {
        val f = file ?: return
        val uri = FileProvider.getUriForFile(context, context.packageName + ".files", f)
        context.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    @Suppress("DEPRECATION")
    private fun currentVersion(context: Context): Long {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()
    }

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
                    return Release(version, a.getString("browser_download_url"))
                }
            }
            return null
        } finally {
            conn.disconnect()
        }
    }

    private fun download(url: String, file: File): Boolean {
        return try {
            file.parentFile?.mkdirs()
            file.parentFile?.listFiles()?.forEach { if (it != file) it.delete() }
            val tmp = File(file.path + ".part")
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.instanceFollowRedirects = true
            conn.connectTimeout = 15_000
            conn.readTimeout = 30_000
            conn.inputStream.use { input -> tmp.outputStream().use { input.copyTo(it, 64 * 1024) } }
            conn.disconnect()
            tmp.length() > 0 && tmp.renameTo(file)
        } catch (e: Exception) {
            false
        }
    }
}
