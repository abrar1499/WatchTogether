package com.abrar.watchtogether

import android.content.Context
import java.util.UUID

/** Stores the user's display name and a permanent random id on the phone. */
class Prefs(context: Context) {
    private val sp = context.getSharedPreferences("watch_prefs", Context.MODE_PRIVATE)

    var name: String
        get() = sp.getString("name", "") ?: ""
        set(value) = sp.edit().putString("name", value).apply()

    /** Video zoom the person last picked with a pinch (0 = whole video, 1 = filled). Starts filled. */
    var zoom: Float
        get() = sp.getFloat("zoom2", 1f)
        set(value) = sp.edit().putFloat("zoom2", value).apply()

    val userId: String
        get() {
            var id = sp.getString("uid", null)
            if (id == null) {
                id = UUID.randomUUID().toString().replace("-", "").take(16)
                sp.edit().putString("uid", id).apply()
            }
            return id
        }
}
