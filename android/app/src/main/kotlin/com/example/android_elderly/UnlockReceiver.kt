package com.example.android_elderly

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class UnlockReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_USER_PRESENT) {
            return
        }

        NetworkGuardService.notifyIfDisconnected(context)
    }
}
