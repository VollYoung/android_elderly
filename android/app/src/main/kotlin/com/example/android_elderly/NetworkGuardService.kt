package com.example.android_elderly

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.telephony.SmsManager
import android.util.Base64
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.Socket
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.net.ssl.SSLSocketFactory

class NetworkGuardService : Service() {
    private lateinit var connectivityManager: ConnectivityManager
    private val handler = Handler(Looper.getMainLooper())
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var lastSnapshot: NetworkSnapshot? = null
    private var hourlyAlertScheduled = false
    private val hourlyAlertRunnable =
        object : Runnable {
            override fun run() {
                val snapshot = currentNetworkSnapshot()
                if (snapshot.hasDisconnectedNetwork) {
                    val message = snapshot.disconnectedMessage(sustained = true)
                    showDisconnectedAlert(message)
                    sendSmsNotice(this@NetworkGuardService, message)
                    sendEmailNoticeAsync(this@NetworkGuardService, message)
                    handler.postDelayed(this, HOURLY_ALERT_INTERVAL_MILLIS)
                } else {
                    hourlyAlertScheduled = false
                }
            }
        }

    override fun onCreate() {
        super.onCreate()
        connectivityManager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        createNotificationChannels()
        startForeground(ONGOING_NOTIFICATION_ID, buildOngoingNotification())
        startNetworkMonitoring()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_GUARD_ENABLED, true)
            .apply()
        publishCurrentState(force = true)
        return START_STICKY
    }

    override fun onDestroy() {
        stopHourlyAlert()
        stopNetworkMonitoring()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startNetworkMonitoring() {
        if (networkCallback != null) {
            return
        }

        val callback =
            object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    publishCurrentState()
                }

                override fun onLost(network: Network) {
                    publishCurrentState()
                }

                override fun onCapabilitiesChanged(
                    network: Network,
                    networkCapabilities: NetworkCapabilities,
                ) {
                    publishCurrentState()
                }

                override fun onUnavailable() {
                    publishCurrentState()
                }
            }

        networkCallback = callback

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            connectivityManager.registerDefaultNetworkCallback(callback)
        } else {
            val request =
                NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build()
            connectivityManager.registerNetworkCallback(request, callback)
        }
    }

    private fun stopNetworkMonitoring() {
        val callback = networkCallback ?: return
        runCatching {
            connectivityManager.unregisterNetworkCallback(callback)
        }
        networkCallback = null
    }

    private fun publishCurrentState(force: Boolean = false) {
        val snapshot = currentNetworkSnapshot()
        val previousSnapshot = lastSnapshot

        if (!force && previousSnapshot == snapshot) {
            return
        }

        lastSnapshot = snapshot

        val alertMessage =
            when {
                previousSnapshot == null && snapshot.hasDisconnectedNetwork ->
                    snapshot.disconnectedMessage(sustained = false)
                previousSnapshot?.hasWifi == true && !snapshot.hasWifi ->
                    "检测到 WiFi 当前不可用"
                previousSnapshot?.hasCellular == true && !snapshot.hasCellular ->
                    "检测到移动数据当前不可用"
                else -> null
            }

        if (alertMessage != null) {
            showDisconnectedAlert(alertMessage)
            sendSmsNotice(this, alertMessage)
            sendEmailNoticeAsync(this, alertMessage)
        }

        if (snapshot.hasDisconnectedNetwork) {
            startHourlyAlert()
        } else {
            stopHourlyAlert()
        }
    }

    private fun startHourlyAlert() {
        if (hourlyAlertScheduled) {
            return
        }
        hourlyAlertScheduled = true
        handler.postDelayed(hourlyAlertRunnable, HOURLY_ALERT_INTERVAL_MILLIS)
    }

    private fun stopHourlyAlert() {
        hourlyAlertScheduled = false
        handler.removeCallbacks(hourlyAlertRunnable)
    }

    private fun currentNetworkSnapshot(): NetworkSnapshot {
        var hasWifi = false
        var hasCellular = false
        val networks = connectivityManager.allNetworks
        for (network in networks) {
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: continue
            val hasInternetCapability =
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            if (!hasInternetCapability) {
                continue
            }
            hasWifi = hasWifi || capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
            hasCellular =
                hasCellular || capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
        }
        return NetworkSnapshot(hasWifi = hasWifi, hasCellular = hasCellular)
    }

    private fun showDisconnectedAlert(message: String) {
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        notificationManager.notify(ALERT_NOTIFICATION_ID, buildAlertNotification(message))
    }

    private fun buildOngoingNotification(): Notification {
        val openAppIntent =
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, GUARD_CHANNEL_ID)
            } else {
                Notification.Builder(this)
            }

        return builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("网络守护运行中")
            .setContentText("正在后台监听 WiFi 和移动数据状态")
            .setContentIntent(openAppIntent)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    private fun buildAlertNotification(message: String): Notification {
        val alertIntent =
            PendingIntent.getActivity(
                this,
                1,
                Intent(this, NetworkAlertActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra(NetworkAlertActivity.EXTRA_MESSAGE, message)
                },
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, ALERT_CHANNEL_ID)
            } else {
                Notification.Builder(this)
            }

        return builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("网络已关闭")
            .setContentText(message)
            .setContentIntent(alertIntent)
            .setFullScreenIntent(alertIntent, true)
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_HIGH)
            .setDefaults(Notification.DEFAULT_ALL)
            .setAutoCancel(true)
            .build()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        notificationManager.createNotificationChannel(
            NotificationChannel(
                GUARD_CHANNEL_ID,
                "网络守护",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "后台网络状态监听"
            },
        )

        notificationManager.createNotificationChannel(
            NotificationChannel(
                ALERT_CHANNEL_ID,
                "网络关闭提醒",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "WiFi 和移动数据不可用时的系统提醒"
            },
        )
    }

    companion object {
        const val PREFERENCES_NAME = "network_guard_preferences"
        const val KEY_GUARD_ENABLED = "guard_enabled"
        private const val KEY_SMS_PHONE_NUMBER = "sms_phone_number"
        private const val KEY_EMAIL_ADDRESS = "email_address"
        private const val KEY_DEVICE_NAME = "device_name"
        private const val KEY_SMTP_HOST = "smtp_host"
        private const val KEY_SMTP_PORT = "smtp_port"
        private const val KEY_SMTP_USERNAME = "smtp_username"
        private const val KEY_SMTP_PASSWORD = "smtp_password"
        private const val KEY_SENDER_EMAIL = "sender_email"
        private const val KEY_SMTP_SECURITY = "smtp_security"
        private const val KEY_EMAIL_LOGS = "email_logs"
        private const val LOG_SEPARATOR = "\u001E"
        private const val MAX_EMAIL_LOG_COUNT = 50
        private const val GUARD_CHANNEL_ID = "network_guard_ongoing"
        private const val ALERT_CHANNEL_ID = "network_guard_alert"
        private const val ONGOING_NOTIFICATION_ID = 1001
        private const val ALERT_NOTIFICATION_ID = 1002
        private const val HOURLY_ALERT_INTERVAL_MILLIS = 60 * 60 * 1000L

        fun start(context: Context) {
            val intent = Intent(context, NetworkGuardService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun notifyIfDisconnected(context: Context) {
            val connectivityManager =
                context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            var hasWifi = false
            var hasCellular = false
            for (network in connectivityManager.allNetworks) {
                val capabilities = connectivityManager.getNetworkCapabilities(network) ?: continue
                val hasInternetCapability =
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                if (!hasInternetCapability) {
                    continue
                }
                hasWifi = hasWifi || capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
                hasCellular =
                    hasCellular || capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
            }
            val snapshot = NetworkSnapshot(hasWifi = hasWifi, hasCellular = hasCellular)
            if (snapshot.hasDisconnectedNetwork) {
                val message = "手机已解锁，${snapshot.disconnectedMessage(sustained = false)}"
                sendSmsNotice(context, message)
                sendEmailNoticeAsync(context, message)
                start(context)
                context.startActivity(
                    Intent(context, NetworkAlertActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        putExtra(NetworkAlertActivity.EXTRA_MESSAGE, message)
                    },
                )
            }
        }

        private fun sendSmsNotice(context: Context, message: String) {
            val phoneNumber =
                context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                    .getString(KEY_SMS_PHONE_NUMBER, "")
                    ?.trim()
                    .orEmpty()

            if (phoneNumber.isEmpty()) {
                return
            }

            if (context.checkSelfPermission(Manifest.permission.SEND_SMS) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                return
            }

            val smsText = "网络守护提醒：$message"
            val smsManager =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    context.getSystemService(SmsManager::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    SmsManager.getDefault()
                }
            val parts = smsManager.divideMessage(smsText)
            smsManager.sendMultipartTextMessage(phoneNumber, null, parts, null, null)
        }

        private fun sendEmailNoticeAsync(context: Context, alertMessage: String) {
            Thread {
                sendEmailNotice(context.applicationContext, alertMessage)
            }.start()
        }

        private fun sendEmailNotice(context: Context, alertMessage: String) {
            val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            val settings = EmailSettings.from(preferences)

            if (settings.recipient.isEmpty()) {
                return
            }

            if (!settings.isConfigured) {
                appendEmailLog(context, "失败：邮件服务器配置不完整，收件人 ${settings.recipient}")
                return
            }

            val disconnectedAt = formatNow()
            val deviceName = settings.deviceName.ifEmpty { "未命名设备" }
            val subject = "Android 网络关闭提醒：$deviceName"
            val body =
                "设备名称：$deviceName\n" +
                    "网络状态：$alertMessage\n" +
                    "检测时间：$disconnectedAt"

            try {
                SmtpClient(settings).use { client ->
                    client.sendMail(
                        from = settings.senderEmail,
                        to = settings.recipient,
                        subject = subject,
                        body = body,
                    )
                }
                appendEmailLog(context, "成功：邮件提醒已发送，设备 $deviceName，收件人 ${settings.recipient}")
            } catch (error: Exception) {
                appendEmailLog(
                    context,
                    "失败：${error.message ?: error.javaClass.simpleName}，设备 $deviceName，收件人 ${settings.recipient}",
                )
            }
        }

        private fun appendEmailLog(context: Context, message: String) {
            val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            val logs =
                preferences.getString(KEY_EMAIL_LOGS, "")
                    ?.split(LOG_SEPARATOR)
                    ?.filter { it.isNotBlank() }
                    ?.toMutableList()
                    ?: mutableListOf()
            logs.add(0, "${formatNow()} $message")
            preferences.edit()
                .putString(KEY_EMAIL_LOGS, logs.take(MAX_EMAIL_LOG_COUNT).joinToString(LOG_SEPARATOR))
                .apply()
        }

        private fun formatNow(): String {
            return SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date())
        }
    }

    private data class EmailSettings(
        val recipient: String,
        val deviceName: String,
        val smtpHost: String,
        val smtpPort: Int,
        val smtpUsername: String,
        val smtpPassword: String,
        val senderEmail: String,
        val security: String,
    ) {
        val isConfigured: Boolean
            get() =
                smtpHost.isNotEmpty() &&
                    smtpPort in 1..65535 &&
                    smtpUsername.isNotEmpty() &&
                    smtpPassword.isNotEmpty() &&
                    senderEmail.isNotEmpty()

        companion object {
            fun from(preferences: android.content.SharedPreferences): EmailSettings {
                return EmailSettings(
                    recipient = preferences.getString(KEY_EMAIL_ADDRESS, "")?.trim().orEmpty(),
                    deviceName = preferences.getString(KEY_DEVICE_NAME, "")?.trim().orEmpty(),
                    smtpHost = preferences.getString(KEY_SMTP_HOST, "")?.trim().orEmpty(),
                    smtpPort = preferences.getInt(KEY_SMTP_PORT, 465),
                    smtpUsername = preferences.getString(KEY_SMTP_USERNAME, "")?.trim().orEmpty(),
                    smtpPassword = preferences.getString(KEY_SMTP_PASSWORD, "").orEmpty(),
                    senderEmail = preferences.getString(KEY_SENDER_EMAIL, "")?.trim().orEmpty(),
                    security = preferences.getString(KEY_SMTP_SECURITY, "ssl") ?: "ssl",
                )
            }
        }
    }

    private class SmtpClient(
        private val settings: EmailSettings,
    ) : AutoCloseable {
        private val socket: Socket =
            if (settings.security == "ssl") {
                SSLSocketFactory.getDefault().createSocket(settings.smtpHost, settings.smtpPort)
            } else {
                Socket(settings.smtpHost, settings.smtpPort)
            }.apply {
                soTimeout = 20000
            }
        private val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8))
        private val writer = OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8)

        init {
            readExpected(220)
            command("EHLO android-elderly.local", 250)
            authenticate()
        }

        fun sendMail(from: String, to: String, subject: String, body: String) {
            command("MAIL FROM:<$from>", 250)
            command("RCPT TO:<$to>", 250, 251)
            command("DATA", 354)
            writeData(buildMessage(from, to, subject, body))
            readExpected(250)
            command("QUIT", 221)
        }

        private fun authenticate() {
            if (settings.smtpUsername.isEmpty() && settings.smtpPassword.isEmpty()) {
                return
            }
            command("AUTH LOGIN", 334)
            command(encodeBase64(settings.smtpUsername), 334)
            command(encodeBase64(settings.smtpPassword), 235)
        }

        private fun command(command: String, vararg expectedCodes: Int) {
            writer.write("$command\r\n")
            writer.flush()
            readExpected(*expectedCodes)
        }

        private fun readExpected(vararg expectedCodes: Int) {
            val response = readResponse()
            if (!expectedCodes.contains(response.code)) {
                throw IllegalStateException("SMTP 返回 ${response.code}: ${response.message}")
            }
        }

        private fun readResponse(): SmtpResponse {
            val lines = mutableListOf<String>()
            while (true) {
                val line = reader.readLine() ?: throw IllegalStateException("SMTP 连接已关闭")
                lines.add(line)
                if (line.length >= 4 && line[3] == ' ') {
                    break
                }
            }
            val code = lines.firstOrNull()?.take(3)?.toIntOrNull() ?: 0
            return SmtpResponse(code, lines.joinToString("\n"))
        }

        private fun writeData(data: String) {
            writer.write(data)
            writer.write("\r\n.\r\n")
            writer.flush()
        }

        private fun buildMessage(from: String, to: String, subject: String, body: String): String {
            val safeBody =
                body.replace("\r\n", "\n")
                    .split("\n")
                    .joinToString("\r\n") { line ->
                        if (line.startsWith(".")) ".$line" else line
                    }
            return listOf(
                "From: <$from>",
                "To: <$to>",
                "Subject: =?UTF-8?B?${encodeBase64(subject)}?=",
                "MIME-Version: 1.0",
                "Content-Type: text/plain; charset=UTF-8",
                "Content-Transfer-Encoding: 8bit",
                "",
                safeBody,
            ).joinToString("\r\n")
        }

        private fun encodeBase64(value: String): String {
            return Base64.encodeToString(value.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        }

        override fun close() {
            runCatching { reader.close() }
            runCatching { writer.close() }
            runCatching { socket.close() }
        }

        private data class SmtpResponse(
            val code: Int,
            val message: String,
        )
    }

    private data class NetworkSnapshot(
        val hasWifi: Boolean,
        val hasCellular: Boolean,
    ) {
        val hasDisconnectedNetwork: Boolean
            get() = !hasWifi || !hasCellular

        fun disconnectedMessage(sustained: Boolean): String {
            val suffix = if (sustained) "已持续不可用" else "当前不可用"
            return when {
                !hasWifi && !hasCellular -> "WiFi 和移动数据$suffix"
                !hasWifi -> "WiFi $suffix"
                else -> "移动数据$suffix"
            }
        }
    }
}
