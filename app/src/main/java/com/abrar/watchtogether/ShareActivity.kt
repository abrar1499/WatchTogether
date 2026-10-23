package com.abrar.watchtogether

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLDecoder
import kotlin.concurrent.thread

/**
 * Receives "Share" from the TikTok, Facebook or YouTube apps. The shared link is resolved to a
 * video and played in the open room (or in the next room the person opens).
 */
class ShareActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = intent?.getStringExtra(Intent.EXTRA_TEXT).orEmpty()
        val link = Regex("https?://\\S+").find(text)?.value
        if (link == null) {
            toast(R.string.share_no_video)
            finish()
            return
        }
        thread {
            DebugLog.log("share", "got $link")
            val found = resolve(link)
            DebugLog.log("share", "resolved to ${found?.first} via ${found?.second}")
            val key = found?.first
            runOnUiThread {
                if (key == null) {
                    toast(R.string.share_no_video)
                } else {
                    PendingShare.key = key
                    PendingShare.url = found?.second
                    if (RoomActivity.isOpen) {
                        startActivity(
                            Intent(this, RoomActivity::class.java)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                        )
                    } else {
                        toast(R.string.share_open_room)
                        startActivity(
                            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                    }
                }
                finish()
            }
        }
    }

    private fun toast(res: Int) = Toast.makeText(this, tr(res), Toast.LENGTH_LONG).show()

    companion object {
        private const val UA =
            "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"

        /** Follows short links (vm.tiktok.com, fb.watch, share links…) until a video page is found. */
        /** The video key and the page address it was found on. */
        fun resolve(start: String): Pair<String, String>? {
            var url = start
            repeat(6) {
                keyOf(url)?.let { return it to url }
                val next = try {
                    val c = URL(url).openConnection() as HttpURLConnection
                    c.instanceFollowRedirects = false
                    c.setRequestProperty("User-Agent", UA)
                    c.connectTimeout = 8000
                    c.readTimeout = 8000
                    val loc = c.getHeaderField("Location")
                    c.disconnect()
                    loc?.let { URL(URL(url), it).toString() }
                } catch (e: Exception) {
                    null
                } ?: return null
                url = next
            }
            return keyOf(url)?.let { it to url }
        }

        private fun keyOf(url: String): String? {
            val plain = try { URLDecoder.decode(url, "UTF-8") } catch (e: Exception) { url }
            val host = try { URL(url).host.lowercase() } catch (e: Exception) { "" }
            val site = when {
                host.contains("tiktok") -> Site.TIKTOK
                host.contains("facebook") || host.contains("fb.watch") -> Site.FACEBOOK
                host.contains("youtube") || host.contains("youtu.be") -> Site.YOUTUBE
                host.contains("netflix") -> Site.NETFLIX
                else -> return null
            }
            if (site == Site.YOUTUBE) return YouTubeLink.extractId(url)
            return Media.keyFromUrl(site, plain)
        }
    }
}

/** A video shared from another app, waiting for a room to play it in. */
object PendingShare {
    @Volatile var key: String? = null
    @Volatile var url: String? = null
}
