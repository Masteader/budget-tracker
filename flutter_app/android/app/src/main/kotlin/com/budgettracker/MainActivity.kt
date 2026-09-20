package com.budgettracker

import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val ENGINE_CACHE_KEY = "main_engine"
        const val SERVICE_CHANNEL = "com.budgettracker/service"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Cache the engine so background SMS listener can invoke Dart methods
        FlutterEngineCache.getInstance().put(ENGINE_CACHE_KEY, flutterEngine)

        // Setup service control channel (start, stop, drainQueue)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SERVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> {
                        val intent = Intent(this, SmsListenerService::class.java)
                        ContextCompat.startForegroundService(this, intent)
                        result.success(true)
                    }
                    "stopService" -> {
                        val intent = Intent(this, SmsListenerService::class.java)
                        stopService(intent)
                        result.success(true)
                    }
                    "drainQueue" -> {
                        val queued = SmsQueue.drainAll(applicationContext)
                        result.success(queued)
                    }
                    "enqueueSms" -> {
                        val args = call.arguments as? Map<*, *>
                        val body = args?.get("body") as? String ?: ""
                        val sender = args?.get("sender") as? String ?: ""
                        val timestamp = (args?.get("timestamp") as? Number)?.toLong() ?: System.currentTimeMillis()
                        SmsQueue.enqueue(applicationContext, body, sender, timestamp)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        FlutterEngineCache.getInstance().remove(ENGINE_CACHE_KEY)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
