package com.erebrus.ai

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var deepLinkSink: EventChannel.EventSink? = null
    private var pendingDeepLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingDeepLink = intent?.dataString

        // Run the disk barrier off the UI thread. flutter_secure_storage's
        // write Future acknowledges apply(); commit() waits for those queued
        // ciphertext writes. This channel never accepts credentials or values.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.erebrus.ai/auth_storage",
            io.flutter.plugin.common.StandardMethodCodec.INSTANCE,
            flutterEngine.dartExecutor.binaryMessenger.makeBackgroundTaskQueue()
        ).setMethodCallHandler { call, result ->
            if (call.method != "flush") {
                result.notImplemented()
            } else {
                try {
                    val names = listOf(
                        "io.erebrus.ai.auth.v2",
                        "FlutterSecureKeyStorage:io.erebrus.ai.auth.v2",
                        "FlutterSecureStorageConfiguration:io.erebrus.ai.auth.v2"
                    )
                    val committed = names.map {
                        getSharedPreferences(it, Context.MODE_PRIVATE).edit().commit()
                    }.all { it }
                    if (committed) result.success(null)
                    else result.error("AUTH_STORAGE_WRITE_FAILED", "Session could not be saved", null)
                } catch (_: Exception) {
                    result.error("AUTH_STORAGE_WRITE_FAILED", "Session could not be saved", null)
                }
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.erebrus.ai/events"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                deepLinkSink = sink
                consumePendingDeepLink()?.let { sink?.success(it) }
            }

            override fun onCancel(arguments: Any?) {
                deepLinkSink = null
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.erebrus.ai/methods"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialLink" -> result.success(consumePendingDeepLink())
                "androidAccelerationInfo" -> result.success(
                    androidAccelerationInfo()
                )
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = intent.dataString ?: return
        val sink = deepLinkSink
        if (sink == null) {
            pendingDeepLink = link
        } else {
            sink.success(link)
        }
    }

    private fun consumePendingDeepLink(): String? {
        val link = pendingDeepLink
        pendingDeepLink = null
        return link
    }

    private fun androidAccelerationInfo(): Map<String, Any> {
        val features = packageManager.systemAvailableFeatures
        val vulkanVersion = features
            .firstOrNull { it.name == "android.hardware.vulkan.version" }
            ?.version ?: 0
        val thermalStatus = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            power.currentThermalStatus
        } else {
            -1
        }
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "hardware" to Build.HARDWARE,
            "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
            "sdk" to Build.VERSION.SDK_INT,
            "buildFingerprint" to Build.FINGERPRINT,
            "vulkanVersion" to vulkanVersion,
            "thermalStatus" to thermalStatus,
        )
    }
}
