package com.bobomusic;

/** Conservative, additive bandwidth extension for markedly band-limited PCM. */
final class BandwidthExtension {
    static final int FRAMES = AudioFft.SIZE;
    private final int rate;
    private final int channels;
    private final double[] real = new double[FRAMES];
    private final double[] imaginary = new double[FRAMES];
    private final double[] window = new double[FRAMES];
    private final AudioFft fft = new AudioFft();
    private final double[] power = new double[FRAMES / 2];
    private final Biquad[][] filters;
    private final double rampStep;
    private double mix;
    private int consecutive;
    private int repairedBlocks;
    private int broadBlocks;
    private int analyzedBlocks;

    BandwidthExtension(int rate, int channels) {
        this.rate = rate;
        this.channels = channels;
        rampStep = 1.0 / (rate * .015);
        filters = new Biquad[channels][];
        for (int channel = 0; channel < channels; channel++) {
            filters[channel] = new Biquad[]{
                new Biquad(rate, 6900, 3.0, 0),
                new Biquad(rate, 6900, 3.0, 0),
                new Biquad(rate, 12300, 0.707, 1),
                new Biquad(rate, 12300, 0.707, 1),
                new Biquad(rate, 17000, 0.707, -1)
            };
        }
        for (int i = 0; i < FRAMES; i++) {
            window[i] = .5 - .5 * Math.cos(2 * Math.PI * i / (FRAMES - 1));
        }
    }

    void process(short[] pcm, int frames) {
        if (frames == FRAMES && hasStrongCutoff(pcm)) {
            consecutive++;
        } else {
            consecutive = 0;
        }
        boolean extending = consecutive >= 3;
        if (extending) repairedBlocks++;
        if (!extending && mix == 0) return;
        for (int frame = 0; frame < frames; frame++) {
            mix = extending ? Math.min(1, mix + rampStep) : Math.max(0, mix - rampStep);
            for (int c = 0; c < channels; c++) {
                int i = frame * channels + c;
                double dry = pcm[i];
                Biquad[] band = filters[c];
                double donor = band[1].next(band[0].next(dry / 32768.0));
                // A quadratic creates a second harmonic. The donor band limits
                // both aliasing and intermodulation before the output filters.
                double harmonic = band[4].next(band[3].next(band[2].next(donor * donor)));
                double correction = Math.max(-250, Math.min(250, harmonic * 81920 * mix));
                // Reduce the added signal as the original approaches full scale.
                correction *= Math.min(1, (32767 - Math.min(32767, Math.abs(dry))) / 250);
                pcm[i] = (short) Math.round(dry + correction);
            }
        }
        if (mix == 0) {
            for (Biquad[] channel : filters) {
                for (Biquad filter : channel) filter.reset();
            }
        }
    }

    boolean hasUsefulOutput() {
        return repairedBlocks >= 15;
    }

    boolean hasBroadSpectrum() {
        return broadBlocks >= 24;
    }

    boolean shouldStopProbing() {
        return hasBroadSpectrum() || (analyzedBlocks >= 30 * rate / FRAMES && !hasUsefulOutput());
    }

    private boolean hasStrongCutoff(short[] samples) {
        analyzedBlocks++;
        java.util.Arrays.fill(power, 0);
        for (int c = 0; c < channels; c++) {
            for (int i = 0; i < FRAMES; i++) {
                real[i] = samples[i * channels + c] * window[i];
                imaginary[i] = 0;
            }
            fft.transform(real, imaginary, false);
            for (int i = 5500 * FRAMES / rate; i < 18500 * FRAMES / rate; i++) {
                power[i] += real[i] * real[i] + imaginary[i] * imaginary[i];
            }
        }
        double donor = energy(5500, 8200);
        double reference = energy(8200, 11800);
        double high = energy(12200, 18500);
        if (high > 1.0e9 && high > .02 * reference) broadBlocks++;
        return donor > 1.0e9
            && reference > donor * .015
            && high < reference * .0025
            && energy(12400, 14400) < energy(10000, 11800) * .004;
    }

    private double energy(int low, int high) {
        double sum = 0;
        for (int index = low * FRAMES / rate; index < high * FRAMES / rate; index++) {
            sum += power[index];
        }
        return sum;
    }

    private static final class Biquad {
        private final double b0, b1, b2, a1, a2;
        private double z1, z2;

        Biquad(int rate, int frequency, double q, int type) {
            double angle = 2 * Math.PI * frequency / rate;
            double cos = Math.cos(angle);
            double alpha = Math.sin(angle) / (2 * q);
            double scale = 1 / (1 + alpha);
            a1 = -2 * cos * scale;
            a2 = (1 - alpha) * scale;
            if (type == 0) {
                b0 = alpha * scale;
                b1 = 0;
                b2 = -b0;
            } else {
                b0 = (1 + type * cos) * scale / 2;
                b1 = -2 * type * b0;
                b2 = b0;
            }
        }

        double next(double input) {
            double output = b0 * input + z1;
            z1 = b1 * input - a1 * output + z2;
            z2 = b2 * input - a2 * output;
            return output;
        }

        void reset() {
            z1 = 0;
            z2 = 0;
        }
    }
}
