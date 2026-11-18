package com.bobomusic

import android.app.NotificationManager
import android.app.job.JobScheduler
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Process
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

/**
 * 继承 AudioServiceActivity 以保持后台播放能力，
 * 同时接管「分享到满满音乐」的文本 / 链接。
 */
class MainActivity : AudioServiceActivity() {

    private var pendingShare: String? = null
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        clearLegacyFriendAlerts()
        // 冷启动时可能已经带了分享内容
        pendingShare = extractSharedText(intent)
    }

    private fun clearLegacyFriendAlerts() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val keys = listOf(
            "flutter.manman_party_watch_friends",
            "flutter.manman_party_watch_last",
            "flutter.manman_party_watch_baseline"
        )
        if (keys.none { prefs.contains(it) }) return

        // Friend alerts were the only feature that scheduled WorkManager jobs.
        val jobs = getSystemService(JOB_SCHEDULER_SERVICE) as JobScheduler
        for (job in jobs.allPendingJobs) {
            if (job.service.className == "androidx.work.impl.background.systemjob.SystemJobService") {
                jobs.cancel(job.id)
            }
        }
        val notifications = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        notifications.cancel(1001)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notifications.deleteNotificationChannel("party_friend_online")
        }
        val editor = prefs.edit()
        for (key in keys) editor.remove(key)
        editor.apply()
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
                    "renderAudio" -> {
                        val path = call.argument<String>("path")
                        val request = call.argument<Int>("request")
                        if (path.isNullOrEmpty() || request == null) {
                            result.error("format", null, null)
                        } else {
                            renderAudio(path, request, result)
                        }
                    }
                    "cancelAudioRender" -> {
                        val request = call.argument<Int>("request")
                        audioRender.get()?.takeIf { it.request == request }?.cancelled = true
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun renderAudio(path: String, request: Int, result: MethodChannel.Result) {
        val job = AudioRender(request)
        if (!audioRender.compareAndSet(null, job)) {
            result.error("busy", null, null)
            return
        }
        val directory = File(cacheDir, "audio-repair")
        audioWorker.execute {
            try {
                Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
                val output = AudioRestoration.render(File(path), directory) { job.cancelled }
                runOnUiThread {
                    result.success(mapOf(
                        "path" to output.file.absolutePath,
                        "effects" to output.effects,
                        "durationMs" to output.durationMs
                    ))
                }
            } catch (error: IOException) {
                val known = setOf("format", "storage", "size", "decode", "timeout", "unchanged", "cancelled")
                val code = error.message?.takeIf { it in known } ?: "decode"
                runOnUiThread { result.error(code, null, null) }
            } catch (_: RuntimeException) {
                runOnUiThread { result.error("decode", null, null) }
            } finally {
                audioRender.compareAndSet(job, null)
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

    private class AudioRender(val request: Int) {
        @Volatile var cancelled: Boolean = false
    }

    companion object {
        private const val CHANNEL = "manman/share"
        private val audioRender = AtomicReference<AudioRender?>()
        private val audioWorker = Executors.newSingleThreadExecutor()
    }
}
