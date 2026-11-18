package com.bobomusic;

final class HeadphoneSpace {
    private final int channels;
    private final float[] delay;
    private final int delayMask;
    private final int earlier;
    private final int later;
    private final float widthFilter;
    private final float reflectionLowPass;
    private final float runningPower;
    private int index;
    private float midBass;
    private float sideBass;
    private float reflective;
    private float midPower;
    private float sidePower;

    HeadphoneSpace(int sampleRate, int channels) {
        this.channels = channels;
        earlier = sampleRate * 8 / 1000;
        later = sampleRate * 13 / 1000;
        delay = new float[Integer.highestOneBit(later) << 1];
        delayMask = delay.length - 1;
        widthFilter = coefficient(sampleRate, 310);
        reflectionLowPass = coefficient(sampleRate, 2400);
        runningPower = coefficient(sampleRate, 3);
    }

    private static float coefficient(int sampleRate, int hz) {
        return (float) (1 - Math.exp(-2 * Math.PI * hz / sampleRate));
    }

    void process(short[] input, int frames, short[] stereo) {
        for (int frame = 0; frame < frames; frame++) {
            float left = input[frame * channels];
            float right = input[frame * channels + channels - 1];
            float mid = (left + right) * .5f;
            float side = (left - right) * .5f;
            midBass += widthFilter * (mid - midBass);
            sideBass += widthFilter * (side - sideBass);
            reflective += reflectionLowPass * (mid - midBass - reflective);
            delay[index] = reflective;
            float taps = delay[(index - earlier) & delayMask]
                - .85f * delay[(index - later) & delayMask];
            index = (index + 1) & delayMask;
            midPower += runningPower * (mid * mid - midPower);
            sidePower += runningPower * (side * side - sidePower);
            float fill = Math.max(0, 1 - 6 * sidePower / (midPower + 1));
            float added = .17f * (side - sideBass) + .043f * fill * taps;
            float room = 32767 - Math.max(Math.abs(left), Math.abs(right));
            float bounded = Math.min(Math.max(0, room), Math.abs(added));
            int offset = Math.round(Math.copySign(bounded, added));
            stereo[frame * 2] = (short) (left + offset);
            stereo[frame * 2 + 1] = (short) (right - offset);
        }
    }
}
