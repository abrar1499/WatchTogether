package com.abrar.watchtogether

import android.content.Context
import android.widget.TextView
import androidx.annotation.StringRes
import com.google.android.material.textfield.TextInputLayout

/**
 * App text that can be changed from the remote settings file without a new build.
 * The key is the string's name (e.g. "create_room"); if the file has no entry,
 * the built-in text is used.
 */
fun Context.tr(@StringRes id: Int, vararg args: Any): String {
    val remote = RemoteConfig.texts[resources.getResourceEntryName(id)]
    if (remote != null) {
        return if (args.isEmpty()) remote else try {
            String.format(remote, *args)
        } catch (e: Exception) {
            getString(id, *args)
        }
    }
    return getString(id, *args)
}

/** Set a view's text from [tr]. */
fun TextView.textR(@StringRes id: Int) {
    text = context.tr(id)
}

/** Set a field's placeholder from [tr]. */
fun TextView.hintR(@StringRes id: Int) {
    hint = context.tr(id)
}

fun TextInputLayout.hintR(@StringRes id: Int) {
    hint = context.tr(id)
}
