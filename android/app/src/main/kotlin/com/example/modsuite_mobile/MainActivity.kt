package com.example.modsuite_mobile

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "modsuite/vrchat_web_cookies"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "readVrchatCookies" -> {
                    val manager = CookieManager.getInstance()
                    val cookies = manager.getCookie("https://vrchat.com")
                    val cookieList = cookies
    ?.split(";")
    ?.map { it.trim() }
    ?.filter { it.isNotEmpty() }
    ?: emptyList<String>()

result.success(cookieList)
                }
                else -> result.notImplemented()
            }
        }
    }
}
