package com.abrar.watchtogether

/** Sites shown as tabs above the search bar. Only YouTube videos can be played in a room for now. */
enum class Site(
    val label: String,
    val domain: String,
    val home: String,
    val searchUrl: String,
    val color: Int
) {
    YOUTUBE("YouTube", "youtube.com", "https://m.youtube.com/",
        "https://m.youtube.com/results?search_query=", 0xFFFF0033.toInt()),
    NETFLIX("Netflix", "netflix.com", "https://www.netflix.com/",
        "https://www.netflix.com/search?q=", 0xFFB20710.toInt()),
    FACEBOOK("Facebook", "facebook.com", "https://m.facebook.com/watch/",
        "https://m.facebook.com/search/videos/?q=", 0xFF1877F2.toInt()),
    TIKTOK("TikTok", "tiktok.com", "https://www.tiktok.com/explore",
        "https://www.tiktok.com/search/video?q=", 0xFF222222.toInt());
}
