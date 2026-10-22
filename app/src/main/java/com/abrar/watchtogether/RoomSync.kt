package com.abrar.watchtogether

import com.google.firebase.database.ChildEventListener
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import com.google.firebase.database.DatabaseReference
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue
import com.google.firebase.database.ValueEventListener

/** What everyone in the room should be watching right now. */
data class PlaybackState(
    val videoId: String,
    val playing: Boolean,
    val position: Double,   // seconds, at the moment of updatedAt
    val updatedAt: Long,    // server time in ms
    val by: String          // userId who made the change
) {
    /** Where the video should be at the given server time. */
    fun positionAt(serverNowMs: Long): Double =
        if (playing) position + ((serverNowMs - updatedAt).coerceAtLeast(0) / 1000.0) else position
}

data class ChatMessage(val uid: String, val name: String, val text: String, val ts: Long)

/**
 * Firebase layout:
 * rooms/{CODE}/createdAt
 * rooms/{CODE}/state      -> PlaybackState
 * rooms/{CODE}/members/{uid} -> name
 * rooms/{CODE}/messages/{pushId} -> ChatMessage
 */
class RoomSync(
    private val code: String,
    private val userId: String,
    private val userName: String
) {
    private val db = FirebaseDatabase.getInstance()
    private val room: DatabaseReference = db.getReference("rooms").child(code)

    private var serverOffsetMs = 0L

    // One presence entry per open room screen, so two screens never erase each other
    private val presenceKey = userId + "_" + (1000..9999).random()
    private val me = room.child("members").child(presenceKey)
    private val listeners = mutableListOf<Pair<com.google.firebase.database.Query, Any>>()

    fun serverNow(): Long = System.currentTimeMillis() + serverOffsetMs

    fun start(
        onState: (PlaybackState) -> Unit,
        onMembers: (List<String>) -> Unit,
        onMessage: (ChatMessage) -> Unit
    ) {
        // Clock difference between this phone and Firebase
        val offsetRef = db.getReference(".info/serverTimeOffset")
        val offsetListener = object : ValueEventListener {
            override fun onDataChange(s: DataSnapshot) {
                serverOffsetMs = (s.getValue(Double::class.java) ?: 0.0).toLong()
            }
            override fun onCancelled(e: DatabaseError) {}
        }
        offsetRef.addValueEventListener(offsetListener)
        listeners += offsetRef to offsetListener

        // Presence: (re)add me every time the connection comes up,
        // and let the server remove me if the connection drops
        val connectedRef = db.getReference(".info/connected")
        val connectedListener = object : ValueEventListener {
            override fun onDataChange(s: DataSnapshot) {
                if (s.getValue(Boolean::class.java) == true) {
                    me.onDisconnect().removeValue()
                    me.setValue(userName)
                }
            }
            override fun onCancelled(e: DatabaseError) {}
        }
        connectedRef.addValueEventListener(connectedListener)
        listeners += connectedRef to connectedListener

        val stateRef = room.child("state")
        val stateListener = object : ValueEventListener {
            override fun onDataChange(s: DataSnapshot) {
                val videoId = s.child("videoId").getValue(String::class.java) ?: return
                onState(
                    PlaybackState(
                        videoId = videoId,
                        playing = s.child("playing").getValue(Boolean::class.java) ?: false,
                        position = s.child("position").getValue(Double::class.java) ?: 0.0,
                        updatedAt = s.child("updatedAt").getValue(Long::class.java) ?: serverNow(),
                        by = s.child("by").getValue(String::class.java) ?: ""
                    )
                )
            }
            override fun onCancelled(e: DatabaseError) {}
        }
        stateRef.addValueEventListener(stateListener)
        listeners += stateRef to stateListener

        val membersRef = room.child("members")
        val membersListener = object : ValueEventListener {
            override fun onDataChange(s: DataSnapshot) {
                onMembers(s.children.mapNotNull { it.getValue(String::class.java) })
            }
            override fun onCancelled(e: DatabaseError) {}
        }
        membersRef.addValueEventListener(membersListener)
        listeners += membersRef to membersListener

        val msgQuery = room.child("messages").limitToLast(100)
        val msgListener = object : ChildEventListener {
            override fun onChildAdded(s: DataSnapshot, prev: String?) {
                val text = s.child("text").getValue(String::class.java) ?: return
                onMessage(
                    ChatMessage(
                        uid = s.child("uid").getValue(String::class.java) ?: "",
                        name = s.child("name").getValue(String::class.java) ?: "?",
                        text = text,
                        ts = s.child("ts").getValue(Long::class.java) ?: 0L
                    )
                )
            }
            override fun onChildChanged(s: DataSnapshot, prev: String?) {}
            override fun onChildRemoved(s: DataSnapshot) {}
            override fun onChildMoved(s: DataSnapshot, prev: String?) {}
            override fun onCancelled(e: DatabaseError) {}
        }
        msgQuery.addChildEventListener(msgListener)
        listeners += msgQuery to msgListener
    }

    fun pushState(videoId: String, playing: Boolean, position: Double) {
        room.child("state").setValue(
            mapOf(
                "videoId" to videoId,
                "playing" to playing,
                "position" to position,
                "updatedAt" to ServerValue.TIMESTAMP,
                "by" to userId
            )
        )
    }

    fun sendMessage(text: String) {
        room.child("messages").push().setValue(
            mapOf(
                "uid" to userId,
                "name" to userName,
                "text" to text.take(500),
                "ts" to ServerValue.TIMESTAMP
            )
        )
    }

    fun stop() {
        for ((query, listener) in listeners) {
            when (listener) {
                is ValueEventListener -> query.removeEventListener(listener)
                is ChildEventListener -> query.removeEventListener(listener)
            }
        }
        listeners.clear()
        me.onDisconnect().cancel()
        me.removeValue()
    }

    companion object {
        private const val CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

        fun newCode(): String = (1..6).map { CHARS.random() }.joinToString("")

        fun createRoom(code: String, onDone: (Boolean) -> Unit) {
            FirebaseDatabase.getInstance().getReference("rooms").child(code)
                .child("createdAt").setValue(ServerValue.TIMESTAMP)
                .addOnSuccessListener { onDone(true) }
                .addOnFailureListener { onDone(false) }
        }

        fun roomExists(code: String, onResult: (Boolean?) -> Unit) {
            FirebaseDatabase.getInstance().getReference("rooms").child(code)
                .child("createdAt").get()
                .addOnSuccessListener { onResult(it.exists()) }
                .addOnFailureListener { onResult(null) }
        }
    }
}
