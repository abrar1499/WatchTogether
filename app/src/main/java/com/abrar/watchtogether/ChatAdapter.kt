package com.abrar.watchtogether

import android.view.Gravity
import android.view.LayoutInflater
import android.view.ViewGroup
import android.widget.LinearLayout
import androidx.recyclerview.widget.RecyclerView
import com.abrar.watchtogether.databinding.ItemChatBinding

class ChatAdapter : RecyclerView.Adapter<ChatAdapter.Holder>() {

    var myUid: String = ""
    private val items = mutableListOf<ChatMessage>()

    fun add(msg: ChatMessage) {
        items += msg
        notifyItemInserted(items.size - 1)
    }

    class Holder(val b: ItemChatBinding) : RecyclerView.ViewHolder(b.root)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
        Holder(ItemChatBinding.inflate(LayoutInflater.from(parent.context), parent, false))

    override fun getItemCount() = items.size

    override fun onBindViewHolder(h: Holder, position: Int) {
        val m = items[position]
        val mine = m.uid == myUid
        h.b.sender.text = if (mine) h.itemView.context.getString(R.string.you) else m.name
        h.b.text.text = m.text
        h.b.bubble.setBackgroundResource(if (mine) R.drawable.bubble_mine else R.drawable.bubble_other)
        (h.b.bubble.layoutParams as LinearLayout.LayoutParams).gravity =
            if (mine) Gravity.END else Gravity.START
        h.b.bubble.requestLayout()
    }
}
