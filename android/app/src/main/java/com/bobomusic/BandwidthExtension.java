package com.bobomusic;

/** Conservative, additive bandwidth extension for markedly band-limited PCM. */
final class BandwidthExtension {
    static final int FRAMES = 1024;
    private final int rate;
    private final int channels;
    private final double[] real = new double[FRAMES];
    private final double[] imaginary = new double[FRAMES];
    private final double[] window = new double[FRAMES];
    private final double[] cosine = new double[FRAMES / 2];
    private final double[] sine = new double[FRAMES / 2];
    private final double[] power = new double[FRAMES / 2];
    private final Biquad[][] filters;
    private double mix;
    private int consecutive;
    private int repairedBlocks;

    BandwidthExtension(int rate, int channels) {
        this.rate = rate;
        this.channels = channels;
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
            if (i < cosine.length) {
                cosine[i] = Math.cos(2 * Math.PI * i / FRAMES);
                sine[i] = -Math.sin(2 * Math.PI * i / FRAMES);
            }
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
        final double step = 1.0 / (rate * .015);
        for (int frame = 0; frame < frames; frame++) {
            mix = extending ? Math.min(1, mix + step) : Math.max(0, mix - step);
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
    }

    boolean hasUsefulOutput() {
        return repairedBlocks >= 15;
    }

    private boolean hasStrongCutoff(short[] samples) {
        java.util.Arrays.fill(power, 0);
        for (int c = 0; c < channels; c++) {
            for (int i = 0; i < FRAMES; i++) {
                int reversed = Integer.reverse(i) >>> 22;
                real[reversed] = samples[i * channels + c] * window[i];
                imaginary[reversed] = 0;
            }
            for (int span = 2; span <= FRAMES; span *= 2) {
                int half = span / 2;
                int stride = FRAMES / span;
                for (int start = 0; start < FRAMES; start += span) {
                    for (int j = 0; j < half; j++) {
                        int a = start + j;
                        int b = a + half;
                        int k = j * stride;
                        double r = real[b] * cosine[k] - imaginary[b] * sine[k];
                        double im = real[b] * sine[k] + imaginary[b] * cosine[k];
                        real[b] = real[a] - r;
                        imaginary[b] = imaginary[a] - im;
                        real[a] += r;
                        imaginary[a] += im;
                    }
                }
            }
            for (int i = 0; i < power.length; i++) {
                power[i] += real[i] * real[i] + imaginary[i] * imaginary[i];
            }
        }
        double donor = energy(5500, 8200);
        double reference = energy(8200, 11800);
        double high = energy(12200, 18500);
        return donor > 1.0e9
            && reference > donor * .015
            && high < reference * .0025;
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
    }
}
