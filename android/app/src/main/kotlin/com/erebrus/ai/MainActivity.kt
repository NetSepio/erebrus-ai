package com.erebrus.ai

import android.content.Intent
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
}
