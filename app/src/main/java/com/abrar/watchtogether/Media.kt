package com.abrar.watchtogether

import java.net.URLEncoder

/**
 * What is playing in a room, as one string shared through Firebase:
 *   "dQw4w9WgXcQ"        YouTube video id (kept plain for older app versions)
 *   "tt:7123456789"      TikTok video id
 *   "fb:<url>"           Facebook video page
 *   "nf:81234567"        Netflix title (each person needs their own login)
 */
object Media {

    private val TIKTOK = Regex("/video/(\\d+)")
    private val FB_REEL = Regex("/reel/(\\d+)")
    private val FB_VIDEOS = Regex("/videos/(?:[^/?#]+/)?(\\d+)")
    private val FB_WATCH = Regex("[?&]v=(\\d+)")
    private val NETFLIX = Regex("/watch/(\\d+)")

    /** Turns a page the person tapped in the search sheet into a room key, or null if it isn't a video. */
    fun keyFromUrl(site: Site, url: String): String? = when (site) {
        Site.YOUTUBE ->
            if (url.contains("/watch") || url.contains("/shorts/")) YouTubeLink.extractId(url) else null
        Site.TIKTOK -> TIKTOK.find(url)?.let { "tt:" + it.groupValues[1] }
        Site.FACEBOOK -> when {
            FB_REEL.containsMatchIn(url) ->
                "fb:https://www.facebook.com/reel/" + FB_REEL.find(url)!!.groupValues[1]
            FB_VIDEOS.containsMatchIn(url) ->
                "fb:https://www.facebook.com/watch/?v=" + FB_VIDEOS.find(url)!!.groupValues[1]
            url.contains("/watch") && FB_WATCH.containsMatchIn(url) ->
                "fb:https://www.facebook.com/watch/?v=" + FB_WATCH.find(url)!!.groupValues[1]
            else -> null
        }
        Site.NETFLIX -> NETFLIX.find(url)?.let { "nf:" + it.groupValues[1] }
    }

    fun siteOf(key: String): Site = when {
        key.startsWith("tt:") -> Site.TIKTOK
        key.startsWith("fb:") -> Site.FACEBOOK
        key.startsWith("nf:") -> Site.NETFLIX
        else -> Site.YOUTUBE
    }

    /** The page the player opens for this key. */
    fun playerUrl(key: String, start: Float): String {
        val rest = key.substringAfter(':')
        return when (siteOf(key)) {
            Site.YOUTUBE -> "https://www.youtube.com/embed/$key" +
                "?autoplay=1&controls=0&rel=0&iv_load_policy=3&playsinline=1&fs=0" +
                "&disablekb=1&modestbranding=1&cc_load_policy=0&start=${start.toInt()}"
            Site.TIKTOK -> "https://www.tiktok.com/player/v1/$rest" +
                "?autoplay=1&controls=0&progress_bar=0&play_button=0&volume_control=0" +
                "&fullscreen_button=0&timestamp=0&loop=0&music_info=0&description=0" +
                "&rel=0&native_context_menu=0&closed_caption=0"
            Site.FACEBOOK -> "https://www.facebook.com/plugins/video.php?href=" +
                URLEncoder.encode(rest, "UTF-8") + "&show_text=false&autoplay=true&mute=false"
            Site.NETFLIX -> "https://www.netflix.com/watch/$rest"
        }
    }

    /** YouTube id for thumbnails, or null for other sites. */
    fun youtubeId(key: String): String? = if (siteOf(key) == Site.YOUTUBE) key else null

    /** Netflix's website refuses phone browsers, so it is opened as a desktop browser. */
    const val DESKTOP_UA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    /** Hosts the player may move between while loading a video. */
    fun allowedHost(host: String): Boolean = listOf(
        "youtube.com", "youtube-nocookie.com", "tiktok.com", "facebook.com", "fbcdn.net", "netflix.com"
    ).any { host == it || host.endsWith(".$it") }
}
