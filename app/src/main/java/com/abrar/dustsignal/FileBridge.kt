package com.abrar.dustsignal

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import android.webkit.JavascriptInterface
import java.io.File

/**
 * Lets the game save a file (the converted soldier) where the player can find it.
 * Exposed to the page as window.DustApp.
 */
class FileBridge(private val context: Context) {

    /** Saves base64 data under [name]. Returns where it went, or "" if it failed. */
    @JavascriptInterface
    fun saveFile(base64: String, name: String): String {
        return try {
            val bytes = Base64.decode(base64, Base64.DEFAULT)
            val safeName = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = context.contentResolver
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, safeName)
                    put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return ""
                val out = resolver.openOutputStream(uri) ?: return ""
                out.use { it.write(bytes) }
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                "the Downloads folder"
            } else {
                // Older Android: the app's own folder needs no storage permission
                val dir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: return ""
                dir.mkdirs()
                val file = File(dir, safeName)
                file.writeBytes(bytes)
                file.absolutePath
            }
        } catch (e: Exception) {
            ""
        }
    }
}
