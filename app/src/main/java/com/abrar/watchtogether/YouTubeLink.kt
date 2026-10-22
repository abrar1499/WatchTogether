package com.abrar.watchtogether

import android.net.Uri

/** Pulls the 11-character video id out of any common YouTube link. */
object YouTubeLink {
    private val ID = Regex("^[A-Za-z0-9_-]{11}$")

    fun extractId(input: String): String? {
        val text = input.trim()
        if (ID.matches(text)) return text

        val uri = try {
            Uri.parse(if (text.startsWith("http")) text else "https://$text")
        } catch (e: Exception) {
            return null
        }
        val host = uri.host?.lowercase() ?: return null
        val segments = uri.pathSegments ?: emptyList()

        val candidate = when {
            host.endsWith("youtu.be") -> segments.firstOrNull()
            host.contains("youtube.com") -> {
                uri.getQueryParameter("v")
                    ?: segments.let { s ->
                        val i = s.indexOfFirst { it in listOf("shorts", "embed", "live", "v") }
                        if (i >= 0) s.getOrNull(i + 1) else null
                    }
            }
            else -> null
        }
        return candidate?.takeIf { ID.matches(it) }
    }
}
