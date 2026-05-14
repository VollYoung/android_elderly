package com.example.android_elderly

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle

class NetworkAlertActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val message = intent.getStringExtra(EXTRA_MESSAGE)
            ?: "检测到 WiFi 或移动数据当前不可用。"

        AlertDialog.Builder(this)
            .setTitle("网络已关闭")
            .setMessage(message)
            .setPositiveButton("知道了") { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()
    }

    companion object {
        const val EXTRA_MESSAGE = "message"
    }
}
