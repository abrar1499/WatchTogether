package com.abrar.dustsignal

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

/** Hears back from Android's installer about a self-update. */
class InstallReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, Int.MIN_VALUE)) {
            PackageInstaller.STATUS_SUCCESS -> Unit   // the app restarts on the new version

            // First update, or a phone that wants confirmation: show Android's install screen
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                try {
                    confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(confirm)
                } catch (e: Exception) {
                    Updater.manualInstall(context)
                }
            }

            // Cancelled by the player: they will be asked again next time
            PackageInstaller.STATUS_FAILURE_ABORTED -> Unit

            else -> try { Updater.manualInstall(context) } catch (e: Exception) { }
        }
    }
}
