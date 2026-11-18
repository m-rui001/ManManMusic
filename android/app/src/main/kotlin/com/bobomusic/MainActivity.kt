package com.bobomusic

import android.content.Intent
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 继承 AudioServiceActivity 以保持后台播放能力，
 * 同时接管「分享到满满音乐」的文本 / 链接。
 */
class MainActivity : AudioServiceActivity() {

    private var pendingShare: String? = null
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 冷启动时可能已经带了分享内容
        pendingShare = extractSharedText(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            if (call.method == "getInitialSharedText") {
                result.success(pendingShare)
                pendingShare = null
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "manman/audio")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "equalizer" -> result.success(PlaybackEffects.apply(
                        call.argument<Int>("session"),
                        call.argument<String>("preset")
                    ))
                    "restoreBandwidth" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("format", null, null)
                        } else {
                            restoreBandwidth(path, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun restoreBandwidth(path: String, result: MethodChannel.Result) {
        if (!restoringAudio.compareAndSet(false, true)) {
            result.error("busy", null, null)
            return
        }
        val directory = File(cacheDir, "audio-repair")
        audioWorker.execute {
            try {
                val output = AudioRestoration.render(File(path), directory)
                runOnUiThread { result.success(output.absolutePath) }
            } catch (error: IOException) {
                val known = setOf("format", "storage", "size", "decode", "timeout", "bandwidth")
                val code = error.message?.takeIf { it in known } ?: "decode"
                runOnUiThread { result.error(code, null, null) }
            } catch (_: RuntimeException) {
                runOnUiThread { result.error("decode", null, null) }
            } finally {
                restoringAudio.set(false)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = extractSharedText(intent) ?: return
        // 直接覆盖也是安全的：Dart 侧只消费一次
        pendingShare = text
        channel?.invokeMethod("onSharedText", text)
    }

    /** 从 ACTION_SEND / ACTION_VIEW 中取出文本或链接 */
    private fun extractSharedText(intent: Intent?): String? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_SEND -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (text.isNullOrBlank()) null else text
            }
            Intent.ACTION_VIEW -> intent.dataString
            else -> null
        }
    }

    companion object {
        private const val CHANNEL = "manman/share"
        private val restoringAudio = AtomicBoolean()
        private val audioWorker = Executors.newSingleThreadExecutor()
    }
}
