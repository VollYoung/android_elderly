package com.example.android_elderly

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (
            action != Intent.ACTION_BOOT_COMPLETED &&
                action != Intent.ACTION_LOCKED_BOOT_COMPLETED
        ) {
            return
        }

        val preferences =
            context.getSharedPreferences(NetworkGuardService.PREFERENCES_NAME, Context.MODE_PRIVATE)
        if (preferences.getBoolean(NetworkGuardService.KEY_GUARD_ENABLED, true)) {
            NetworkGuardService.start(context)
        }
    }
}
