package com.blackringsecurity.nabby

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val ACTION_DISCONNECT_ALL = "com.blackringsecurity.nabby.DISCONNECT_ALL"
        const val ALERT_CHANNEL_ID = "ssh_alerts"
    }

    private var channel: MethodChannel? = null
    private var alertId = 100

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nabby/keepalive").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        requestNotificationPermission()
                        val count = call.argument<Int>("count") ?: 1
                        val intent = Intent(this@MainActivity, SshKeepAliveService::class.java)
                            .putExtra(SshKeepAliveService.EXTRA_COUNT, count)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this@MainActivity, SshKeepAliveService::class.java))
                        result.success(null)
                    }
                    "notify" -> {
                        showAlert(call.argument<String>("title") ?: "Nabby", call.argument<String>("text") ?: "")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == ACTION_DISCONNECT_ALL) {
            intent.action = null
            channel?.invokeMethod("disconnectAll", null)
            stopService(Intent(this, SshKeepAliveService::class.java))
        }
    }

    private fun showAlert(title: String, text: String) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(ALERT_CHANNEL_ID, "Connection alerts", NotificationManager.IMPORTANCE_DEFAULT)
                    .apply { description = "Tells you when an SSH session drops in the background" }
            )
        }
        val open = PendingIntent.getActivity(
            this, 1,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, ALERT_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(this)
        }
        nm.notify(
            alertId++,
            builder.setSmallIcon(R.drawable.ic_stat_terminal)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
        )
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }
}
