package com.bobomusic;

import java.util.Arrays;

/** Linked-channel spectral attenuation for quiet, steady broadband noise. */
final class NoiseReduction {
    static final int HOP = AudioFft.SIZE / 2;
    private final int channels;
    private final AudioFft fft = new AudioFft();
    private final double[] window = new double[AudioFft.SIZE];
    private final double[] windowPower = new double[AudioFft.SIZE];
    private final double[][] real;
    private final double[][] imaginary;
    private final short[] previous;
    private final double[][] overlap;
    private final double[] power = new double[HOP + 1];
    private final double[] profile = new double[HOP + 1];
    private final double[] attenuation = new double[HOP + 1];
    private final int firstBin;
    private final int lastBin;
    private int profileFrames;
    private int appliedFrames;
    private double lastFramePower;

    NoiseReduction(int sampleRate, int channels) {
        this.channels = channels;
        firstBin = 750 * AudioFft.SIZE / sampleRate;
        lastBin = 14000 * AudioFft.SIZE / sampleRate;
        real = new double[channels][AudioFft.SIZE];
        imaginary = new double[channels][AudioFft.SIZE];
        overlap = new double[channels][HOP];
        previous = new short[HOP * channels];
        for (int i = 0; i < window.length; i++) {
            window[i] = Math.sin(Math.PI * (i + .5) / window.length);
            windowPower[i] = window[i] * window[i];
        }
    }

    // The output is the previous hop. Start and finish with one zero-padded hop.
    void advance(short[] input, short[] output) {
        Arrays.fill(power, 0);
        double timePower = 0;
        for (int c = 0; c < channels; c++) {
            double[] re = real[c];
            double[] im = imaginary[c];
            Arrays.fill(im, 0);
            for (int i = 0; i < HOP; i++) {
                double old = previous[i * channels + c];
                double next = input[i * channels + c];
                timePower += old * old + next * next;
                re[i] = old * window[i];
                re[i + HOP] = next * window[i + HOP];
            }
            fft.transform(re, im, false);
            for (int bin = firstBin - 1; bin <= lastBin + 1; bin++) {
                power[bin] += re[bin] * re[bin] + im[bin] * im[bin];
            }
        }
        updateGains(timePower / (AudioFft.SIZE * channels));

        if (profileFrames < 16) {
            passThrough(input, output);
            return;
        }

        for (int c = 0; c < channels; c++) {
            double[] re = real[c];
            double[] im = imaginary[c];
            for (int bin = firstBin; bin <= lastBin; bin++) {
                int negative = AudioFft.SIZE - bin;
                double gain = 1 - attenuation[bin];
                re[bin] *= gain;
                im[bin] *= gain;
                re[negative] *= gain;
                im[negative] *= gain;
            }
            fft.transform(re, im, true);
            double[] tail = overlap[c];
            for (int i = 0; i < HOP; i++) {
                double sample = tail[i] + re[i] * window[i] / AudioFft.SIZE;
                output[i * channels + c] =
                    (short) Math.max(-32768, Math.min(32767, Math.round(sample)));
                tail[i] = re[i + HOP] * window[i + HOP] / AudioFft.SIZE;
            }
        }
        System.arraycopy(input, 0, previous, 0, previous.length);
    }

    private void passThrough(short[] input, short[] output) {
        System.arraycopy(previous, 0, output, 0, previous.length);
        for (int c = 0; c < channels; c++) {
            for (int i = 0; i < HOP; i++) {
                overlap[c][i] = input[i * channels + c] * windowPower[i + HOP];
            }
        }
        System.arraycopy(input, 0, previous, 0, previous.length);
    }

    private void updateGains(double meanSquare) {
        double total = 0;
        double peak = 0;
        for (int bin = firstBin; bin <= lastBin; bin++) {
            total += power[bin];
            peak = Math.max(peak, power[bin]);
        }
        // A narrow, sustained musical partial must not become the noise profile.
        boolean steady = meanSquare < lastFramePower * 1.5 && lastFramePower < meanSquare * 1.5;
        double minimumBroadbandPower = .035 * meanSquare * channels * AudioFft.SIZE * AudioFft.SIZE;
        if (steady && meanSquare >= 45 && meanSquare <= 90_000
                && peak < .075 * total && total > minimumBroadbandPower) {
            profileFrames++;
            double weight = 1.0 / Math.min(48, profileFrames);
            for (int bin = firstBin; bin <= lastBin; bin++) {
                profile[bin] += weight * (nearbyPower(bin) - profile[bin]);
            }
        }
        boolean transientFrame = meanSquare > lastFramePower * 2;
        lastFramePower = meanSquare;
        if (profileFrames < 16) return;
        boolean changed = false;
        for (int bin = firstBin; bin <= lastBin; bin++) {
            double signal = nearbyPower(bin);
            double raw = Math.min(.38, .42 * profile[bin] / (signal + 1));
            // Blend the outer bins to avoid a sharp edge in the processed band.
            double edge = Math.min(1, Math.min(bin - firstBin, lastBin - bin) / 8.0);
            double target = transientFrame ? 0 : edge * raw;
            double weight = target > attenuation[bin] ? .21 : .63;
            attenuation[bin] += weight * (target - attenuation[bin]);
            changed |= attenuation[bin] > .035 && signal > 20;
        }
        if (changed) appliedFrames++;
    }

    private double nearbyPower(int bin) {
        return (power[bin - 1] + 2 * power[bin] + power[bin + 1]) * .25;
    }

    boolean hasUsefulOutput() {
        return appliedFrames >= 12;
    }
}
