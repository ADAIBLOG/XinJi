package com.adai.xinji

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val POWER_CHANNEL = "com.adai.xinji/power"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, POWER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 是否已加入电池优化白名单（未加入时部分系统会冻结后台闹钟）。
                    "isIgnoringBatteryOptimizations" -> {
                        val powerManager =
                            getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(
                            powerManager.isIgnoringBatteryOptimizations(packageName),
                        )
                    }
                    // 申请加入白名单；部分 ROM 会直接跳转到「应用信息」。
                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName"),
                                ),
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                        Uri.parse("package:$packageName"),
                                    ),
                                )
                                result.success(false)
                            } catch (e2: Exception) {
                                result.error("unavailable", e2.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
