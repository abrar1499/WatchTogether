package com.abrar.watchtogether

import android.app.Activity
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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/**
 * Keeps the app up to date by itself.
 *
 * On start it checks GitHub Releases (tag "v<number>" = versionCode). A newer APK is
 * downloaded quietly in the background, then installed while the person is on the main
 * screen (never in the middle of watching). On Android 12+ the installs after the first
 * one need no tap at all; older phones show the normal install screen.
 */
object Updater {

    private const val LATEST_URL =
        "https://api.github.com/repos/abrar1499/WatchTogether/releases/latest"

    private val main = Handler(Looper.getMainLooper())
    private var checkedThisSession = false
    private var downloading = false

    // A downloaded update waiting for a good moment to install
    private var readyFile: File? = null
    private var readyVersion = 0
    private var waitingForPermission = false

    private data class Release(val version: Int, val apkUrl: String)

    /** Called when the app starts: quietly check, download, and install when it's a good moment. */
    fun checkOnStart(activity: Activity) {
        if (checkedThisSession) return
        checkedThisSession = true
        check(activity, manual = false)
    }

    /** Called when someone taps the version number. */
    fun check(activity: Activity, manual: Boolean) {
        if (downloading) return
        val app = activity.applicationContext
        thread {
            val release = try { fetchLatest() } catch (e: Exception) { null }
            when {
                release == null -> main.post { if (manual) toast(app, R.string.update_check_failed) }
                release.version <= BuildConfig.VERSION_CODE ->
                    main.post { if (manual) toast(app, R.string.update_none) }
                else -> {
                    if (manual) main.post { toast(app, R.string.update_downloading) }
                    val file = File(app.getExternalFilesDir("updates"), "update-${release.version}.apk")
                    val ok = readyVersion == release.version && file.length() > 0 ||
                        download(release.apkUrl, file)
                    main.post {
                        if (!ok) {
                            if (manual) toast(app, R.string.update_download_failed)
                            return@post
                        }
                        readyFile = file
                        readyVersion = release.version
                        if (isResumed(activity)) installNow(activity)
                    }
                }
            }
        }
    }

    /** The main screen came to the front: a good moment to install a waiting update. */
    fun onMainResumed(activity: Activity) {
        if (readyFile == null) return
        if (waitingForPermission && !canInstall(activity)) return
        waitingForPermission = false
        installNow(activity)
    }

    private fun isResumed(activity: Activity): Boolean =
        !activity.isFinishing && !activity.isDestroyed &&
            (activity as? LifecycleOwner)?.lifecycle?.currentState?.isAtLeast(Lifecycle.State.RESUMED) == true

    private fun canInstall(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()

    private fun installNow(activity: Activity) {
        val file = readyFile ?: return
        if (!canInstall(activity)) {
            // One time only: Android needs "Install unknown apps" allowed for this app
            if (waitingForPermission) return
            waitingForPermission = true
            MaterialAlertDialogBuilder(activity)
                .setTitle(activity.tr(R.string.update_permission_title))
                .setMessage(activity.tr(R.string.update_permission_message))
                .setPositiveButton(activity.tr(R.string.update_permission_ok)) { _, _ ->
                    activity.startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:" + activity.packageName)
                        )
                    )
                }
                .setNegativeButton(activity.tr(R.string.update_later)) { _, _ -> waitingForPermission = false }
                .show()
            return
        }
        readyFile = null
        toast(activity, R.string.update_installing)
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

    // Kept so the receiver can fall back to the classic install screen if needed
    private var lastFile: File? = null

    /** Classic install screen, used if the quiet install isn't possible on this phone. */
    fun manualInstall(context: Context, file: File? = lastFile) {
        val f = file ?: return
        val uri = FileProvider.getUriForFile(context, context.packageName + ".files", f)
        context.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        )
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
        downloading = true
        return try {
            file.parentFile?.mkdirs()
            // Remove older downloads
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
        } finally {
            downloading = false
        }
    }

    private fun toast(context: Context, res: Int) =
        Toast.makeText(context, context.tr(res), Toast.LENGTH_LONG).show()
}
