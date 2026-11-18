package com.bobomusic

import android.media.audiofx.AudioEffect
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Equalizer
import android.os.Build
import androidx.annotation.RequiresApi

internal object PlaybackEffects {
    private var effect: AudioEffect? = null
    private var activeSession: Int? = null
    private var activePreset: String? = null

    fun apply(session: Int?, preset: String?): Boolean {
        if (preset == "night" && Build.VERSION.SDK_INT < 28) return false
        if (session == null || session <= 0 || preset == "original") {
            release()
            return true
        }

        if (activeSession == session && activePreset == preset) return true
        var candidate: AudioEffect? = null
        return try {
            val previous = effect
            if (preset == "night" && Build.VERSION.SDK_INT >= 28) {
                candidate = DynamicsProcessing(0, session, nightConfig())
            } else {
                val equalizer = if (previous is Equalizer && activeSession == session) {
                    previous
                } else {
                    Equalizer(0, session)
                }
                candidate = equalizer
                configureEqualizer(equalizer, preset)
            }
            check(checkNotNull(candidate).setEnabled(true) == AudioEffect.SUCCESS)
            if (previous !== candidate) previous?.release()
            effect = candidate
            activeSession = session
            activePreset = preset
            true
        } catch (_: RuntimeException) {
            if (candidate !== effect) candidate?.release()
            if (activeSession != session || candidate === effect) release()
            false
        }
    }

    private fun configureEqualizer(effect: Equalizer, preset: String?) {
        val range = effect.bandLevelRange
        for (index in 0 until effect.numberOfBands.toInt()) {
            val band = index.toShort()
            val hz = effect.getCenterFreq(band) / 1000
            // Attenuation preserves headroom for loud masters. Android levels are in millibels.
            val level = when (preset) {
                "clear" -> if (hz < 200) -200 else if (hz < 700) -130 else 0
                "warm" -> if (hz > 5000) -230 else if (hz > 1800) -110 else 0
                else -> 0
            }
            effect.setBandLevel(band, level.coerceIn(range[0].toInt(), range[1].toInt()).toShort())
        }
    }

    @RequiresApi(28)
    private fun nightConfig(): DynamicsProcessing.Config {
        val config = DynamicsProcessing.Config.Builder(
            DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
            2,
            false, 0,
            true, 1,
            false, 0,
            true
        ).setLimiterAllChannelsTo(
            DynamicsProcessing.Limiter(true, true, 0, 1f, 90f, 12f, -1.5f, 0f)
        ).build()
        // One broadband band avoids independently altering bass, mids and treble.
        val quietListening = DynamicsProcessing.MbcBand(
            true, 22000f, 18f, 160f, 2.2f, -19f, 6f, -90f, 1f, 0f, 2f
        )
        config.setMbcBandAllChannelsTo(0, quietListening)
        return config
    }

    private fun release() {
        effect?.release()
        effect = null
        activeSession = null
        activePreset = null
    }
}
