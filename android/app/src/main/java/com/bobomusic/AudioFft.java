package com.bobomusic;

final class AudioFft {
    static final int SIZE = 1024;
    private final double[] cosine = new double[SIZE / 2];
    private final double[] sine = new double[SIZE / 2];
    private final int[] reversed = new int[SIZE];

    AudioFft() {
        for (int i = 0; i < SIZE; i++) {
            reversed[i] = Integer.reverse(i) >>> 22;
            if (i < cosine.length) {
                cosine[i] = Math.cos(2 * Math.PI * i / SIZE);
                sine[i] = -Math.sin(2 * Math.PI * i / SIZE);
            }
        }
    }

    void transform(double[] real, double[] imaginary, boolean inverse) {
        for (int i = 0; i < SIZE; i++) {
            int j = reversed[i];
            if (i >= j) continue;
            double r = real[i];
            double im = imaginary[i];
            real[i] = real[j];
            imaginary[i] = imaginary[j];
            real[j] = r;
            imaginary[j] = im;
        }
        for (int span = 2; span <= SIZE; span *= 2) {
            int half = span / 2;
            int stride = SIZE / span;
            for (int start = 0; start < SIZE; start += span) {
                for (int j = 0; j < half; j++) {
                    int a = start + j;
                    int b = a + half;
                    int k = j * stride;
                    double sin = inverse ? -sine[k] : sine[k];
                    double r = real[b] * cosine[k] - imaginary[b] * sin;
                    double im = real[b] * sin + imaginary[b] * cosine[k];
                    real[b] = real[a] - r;
                    imaginary[b] = imaginary[a] - im;
                    real[a] += r;
                    imaginary[a] += im;
                }
            }
        }
    }
}
