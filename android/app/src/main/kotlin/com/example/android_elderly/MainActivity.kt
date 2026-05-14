package com.example.android_elderly

import android.Manifest
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var connectivityManager: ConnectivityManager
    private lateinit var preferences: SharedPreferences
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var lastHasWifiOrCellular: Boolean? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        connectivityManager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        preferences = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
        requestRequiredPermissionsIfNeeded()
        NetworkGuardService.start(this)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SETTINGS_CHANNEL,
        ).setMethodCallHandler(::handleMethodCall)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NETWORK_EVENTS_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    eventSink = events
                    publishCurrentState(forcedEventType = "current_state")
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            },
        )
    }

    override fun onResume() {
        super.onResume()
        startNetworkMonitoring()
        publishCurrentState(forcedEventType = "current_state")
    }

    override fun onPause() {
        stopNetworkMonitoring()
        super.onPause()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getEmailAddress" -> {
                result.success(preferences.getString(KEY_EMAIL_ADDRESS, "") ?: "")
            }

            "getSmsPhoneNumber" -> {
                result.success(preferences.getString(KEY_SMS_PHONE_NUMBER, "") ?: "")
            }

            "getDeviceName" -> {
                result.success(preferences.getString(KEY_DEVICE_NAME, "") ?: "")
            }

            "getEmailServerSettings" -> {
                result.success(
                    mapOf(
                        "smtpHost" to (preferences.getString(KEY_SMTP_HOST, "") ?: ""),
                        "smtpPort" to preferences.getInt(KEY_SMTP_PORT, 465),
                        "smtpUsername" to (preferences.getString(KEY_SMTP_USERNAME, "") ?: ""),
                        "smtpPassword" to (preferences.getString(KEY_SMTP_PASSWORD, "") ?: ""),
                        "senderEmail" to (preferences.getString(KEY_SENDER_EMAIL, "") ?: ""),
                        "security" to (preferences.getString(KEY_SMTP_SECURITY, "ssl") ?: "ssl"),
                    ),
                )
            }

            "getEmailLogs" -> {
                result.success(readEmailLogs())
            }

            "appendEmailLog" -> {
                val log = call.argument<String>("log")?.trim().orEmpty()
                if (log.isNotEmpty()) {
                    val logs = readEmailLogs().toMutableList()
                    logs.add(0, log)
                    preferences.edit()
                        .putString(KEY_EMAIL_LOGS, logs.take(MAX_EMAIL_LOG_COUNT).joinToString(LOG_SEPARATOR))
                        .apply()
                }
                result.success(null)
            }

            "clearEmailLogs" -> {
                preferences.edit().remove(KEY_EMAIL_LOGS).apply()
                result.success(null)
            }

            "saveEmailAddress" -> {
                val emailAddress = call.argument<String>("emailAddress")?.trim().orEmpty()
                preferences.edit().putString(KEY_EMAIL_ADDRESS, emailAddress).apply()
                result.success(null)
            }

            "saveEmailServerSettings" -> {
                val smtpHost = call.argument<String>("smtpHost")?.trim().orEmpty()
                val smtpPort = call.argument<Int>("smtpPort") ?: 465
                val smtpUsername = call.argument<String>("smtpUsername")?.trim().orEmpty()
                val smtpPassword = call.argument<String>("smtpPassword").orEmpty()
                val senderEmail = call.argument<String>("senderEmail")?.trim().orEmpty()
                val security = call.argument<String>("security")?.trim().orEmpty().ifEmpty { "ssl" }
                preferences.edit()
                    .putString(KEY_SMTP_HOST, smtpHost)
                    .putInt(KEY_SMTP_PORT, smtpPort)
                    .putString(KEY_SMTP_USERNAME, smtpUsername)
                    .putString(KEY_SMTP_PASSWORD, smtpPassword)
                    .putString(KEY_SENDER_EMAIL, senderEmail)
                    .putString(KEY_SMTP_SECURITY, security)
                    .apply()
                result.success(null)
            }

            "saveSmsPhoneNumber" -> {
                val phoneNumber = call.argument<String>("phoneNumber")?.trim().orEmpty()
                preferences.edit().putString(KEY_SMS_PHONE_NUMBER, phoneNumber).apply()
                result.success(null)
            }

            "saveDeviceName" -> {
                val deviceName = call.argument<String>("deviceName")?.trim().orEmpty()
                preferences.edit().putString(KEY_DEVICE_NAME, deviceName).apply()
                result.success(null)
            }

            "getCurrentNetworkState" -> {
                result.success(buildStatePayload("current_state"))
            }

            "startGuardService" -> {
                requestRequiredPermissionsIfNeeded()
                NetworkGuardService.start(this)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun readEmailLogs(): List<String> {
        return preferences.getString(KEY_EMAIL_LOGS, "")
            ?.split(LOG_SEPARATOR)
            ?.filter { it.isNotBlank() }
            ?: emptyList()
    }

    private fun requestRequiredPermissionsIfNeeded() {
        val permissions = mutableListOf<String>()

        if (checkSelfPermission(Manifest.permission.SEND_SMS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            permissions.add(Manifest.permission.SEND_SMS)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        if (permissions.isNotEmpty()) {
            requestPermissions(permissions.toTypedArray(), 100)
        }
    }

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

    private fun publishCurrentState(forcedEventType: String? = null) {
        val hasWifiOrCellular = hasWifiOrCellularConnection()
        val previousState = lastHasWifiOrCellular

        if (forcedEventType == null && previousState == hasWifiOrCellular) {
            return
        }

        val eventType =
            forcedEventType
                ?: when {
                    previousState == true && !hasWifiOrCellular -> "all_disconnected"
                    previousState == false && hasWifiOrCellular -> "network_restored"
                    else -> "state_changed"
                }

        lastHasWifiOrCellular = hasWifiOrCellular
        val payload = buildStatePayload(eventType, hasWifiOrCellular)
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    private fun buildStatePayload(
        eventType: String,
        hasWifiOrCellular: Boolean = hasWifiOrCellularConnection(),
    ): Map<String, Any> {
        return mapOf(
            "eventType" to eventType,
            "hasWifiOrCellular" to hasWifiOrCellular,
        )
    }

    private fun hasWifiOrCellularConnection(): Boolean {
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
        return hasWifi && hasCellular
    }

    companion object {
        private const val SETTINGS_CHANNEL = "com.example.android_elderly/settings"
        private const val NETWORK_EVENTS_CHANNEL = "com.example.android_elderly/network_events"
        private const val PREFERENCES_NAME = "network_guard_preferences"
        private const val KEY_EMAIL_ADDRESS = "email_address"
        private const val KEY_SMS_PHONE_NUMBER = "sms_phone_number"
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
    }
}
