package com.bobomusic;

import android.media.AudioFormat;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.os.Build;
import android.os.SystemClock;

import java.io.File;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.ShortBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

final class AudioRestoration {
    private static final int MAX_PCM_BYTES = 384 * 1024 * 1024;
    private static final int PROBE_SECONDS = 8;

    static final class Rendered {
        final File file;
        final List<String> effects;
        final long durationMs;

        Rendered(File file, List<String> effects, long durationMs) {
            this.file = file;
            this.effects = effects;
            this.durationMs = durationMs;
        }
    }

    interface Cancellation {
        boolean isCancelled();
    }

    static Rendered render(File input, File directory, Cancellation cancellation)
            throws IOException {
        if (cancellation.isCancelled()) throw failure("cancelled");
        if (!directory.isDirectory() && !directory.mkdirs()) throw failure("storage");
        File[] previous = directory.listFiles();
        if (previous != null) {
            long cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L;
            for (File file : previous) {
                if (file.lastModified() < cutoff) file.delete();
            }
        }
        File output = File.createTempFile("repair-", ".wav", directory);
        boolean complete = false;
        try {
            Rendered rendered = decode(input, output, cancellation);
            complete = true;
            return rendered;
        } finally {
            if (!complete) output.delete();
        }
    }

    private static Rendered decode(File input, File output, Cancellation cancellation)
            throws IOException {
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec decoder = null;
        try (RandomAccessFile wav = new RandomAccessFile(output, "rw")) {
            extractor.setDataSource(input.getAbsolutePath());
            MediaFormat format = selectTrack(extractor);
            int rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE);
            int channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
            String mime = format.getString(MediaFormat.KEY_MIME);
            if ((rate != 44100 && rate != 48000) || channels < 1 || channels > 2) {
                throw failure("format");
            }
            if (Build.VERSION.SDK_INT >= 24) {
                format.setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT);
            }
            decoder = MediaCodec.createDecoderByType(mime);
            decoder.configure(format, null, null, 0);
            decoder.start();
            long durationMs = format.containsKey(MediaFormat.KEY_DURATION)
                ? format.getLong(MediaFormat.KEY_DURATION) / 1000 : 0;
            boolean canExtend = !"audio/flac".equals(mime);
            WavWriter writer = new WavWriter(wav, output, rate, channels, canExtend,
                durationMs, cancellation);
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            boolean inputEnded = false;
            boolean outputEnded = false;
            long deadline = SystemClock.elapsedRealtime() + 180_000;
            while (!outputEnded) {
                if (cancellation.isCancelled()) throw failure("cancelled");
                if (SystemClock.elapsedRealtime() >= deadline) throw failure("timeout");
                if (!inputEnded) {
                    int index = decoder.dequeueInputBuffer(5000);
                    if (index >= 0) {
                        ByteBuffer buffer = decoder.getInputBuffer(index);
                        if (buffer == null) throw failure("decode");
                        buffer.clear();
                        int size = extractor.readSampleData(buffer, 0);
                        inputEnded = size < 0;
                        decoder.queueInputBuffer(index, 0, Math.max(0, size),
                            inputEnded ? 0 : extractor.getSampleTime(),
                            inputEnded ? MediaCodec.BUFFER_FLAG_END_OF_STREAM : 0);
                        if (!inputEnded) extractor.advance();
                    }
                }
                int index = decoder.dequeueOutputBuffer(info, 5000);
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    verifyOutput(decoder.getOutputFormat(), rate, channels);
                } else if (index >= 0) {
                    ByteBuffer buffer = decoder.getOutputBuffer(index);
                    if (buffer != null && info.size > 0
                            && (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                        buffer.limit(info.offset + info.size);
                        buffer.position(info.offset);
                        writer.write(buffer.order(ByteOrder.nativeOrder()));
                    }
                    decoder.releaseOutputBuffer(index, false);
                    outputEnded = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                }
            }
            return writer.finish();
        } finally {
            try {
                if (decoder != null) decoder.release();
            } finally {
                extractor.release();
            }
        }
    }

    private static MediaFormat selectTrack(MediaExtractor extractor)
            throws IOException {
        for (int index = 0; index < extractor.getTrackCount(); index++) {
            MediaFormat format = extractor.getTrackFormat(index);
            String mime = format.getString(MediaFormat.KEY_MIME);
            if ("audio/mp4a-latm".equals(mime) || "audio/mpeg".equals(mime)
                    || "audio/flac".equals(mime)) {
                extractor.selectTrack(index);
                return format;
            }
        }
        throw failure("format");
    }

    private static void verifyOutput(MediaFormat format, int rate, int channels)
            throws IOException {
        if (format.getInteger(MediaFormat.KEY_SAMPLE_RATE) != rate
                || format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) != channels
                || (Build.VERSION.SDK_INT >= 24
                    && format.containsKey(MediaFormat.KEY_PCM_ENCODING)
                    && format.getInteger(MediaFormat.KEY_PCM_ENCODING)
                        != AudioFormat.ENCODING_PCM_16BIT)) {
            throw failure("format");
        }
    }

    private static IOException failure(String reason) {
        return new IOException(reason);
    }

    private static final class WavWriter {
        private final RandomAccessFile file;
        private final File output;
        private final int rate;
        private final int channels;
        private final long durationMs;
        private final Cancellation cancellation;
        private final short[] samples;
        private final short[] stereo;
        private final short[] hop;
        private final short[] denoised;
        private final List<String> effects = new ArrayList<>(3);
        private final byte[] encoded = new byte[64 * 1024];
        private final ShortBuffer encodedSamples = ByteBuffer.wrap(encoded)
            .order(ByteOrder.LITTLE_ENDIAN).asShortBuffer();
        private BandwidthExtension extension;
        private NoiseReduction noise;
        private HeadphoneSpace space;
        private short[] probe;
        private int probeLength;
        private int length;
        private int pcmBytes;
        private int previousFrames;
        private int outputChannels;
        private double midPower;
        private double sidePower;

        WavWriter(RandomAccessFile file, File output, int rate, int channels,
                boolean canExtend, long durationMs, Cancellation cancellation) {
            this.file = file;
            this.output = output;
            this.rate = rate;
            this.channels = channels;
            this.durationMs = durationMs;
            this.cancellation = cancellation;
            extension = canExtend ? new BandwidthExtension(rate, channels) : null;
            noise = new NoiseReduction(rate, channels);
            samples = new short[BandwidthExtension.FRAMES * channels];
            probe = new short[rate * PROBE_SECONDS / BandwidthExtension.FRAMES * samples.length];
            stereo = new short[BandwidthExtension.FRAMES * 2];
            hop = new short[NoiseReduction.HOP * channels];
            denoised = new short[hop.length];
        }

        void write(ByteBuffer decoded) throws IOException {
            if ((decoded.remaining() & 1) != 0) throw failure("decode");
            ShortBuffer shorts = decoded.asShortBuffer();
            while (shorts.hasRemaining()) {
                int count = Math.min(samples.length - length, shorts.remaining());
                shorts.get(samples, length, count);
                length += count;
                if (length == samples.length) flush();
            }
        }

        private void flush() throws IOException {
            if (length % channels != 0) throw failure("decode");
            int frames = length / channels;
            if (probe == null) {
                process(frames);
            } else {
                if (extension != null && length == samples.length) extension.probe(samples);
                if (!noise.hasUsefulOutput()) {
                    for (int offset = 0; offset < length; offset += hop.length) {
                        fillHop(offset, Math.min(hop.length, length - offset));
                        noise.probe(hop);
                    }
                }
                // Sample the stereo balance without performing the effect during detection.
                for (int frame = 0; frame < frames; frame += 4) {
                    int left = samples[frame * channels];
                    int right = samples[frame * channels + channels - 1];
                    double mid = left + right;
                    double side = left - right;
                    midPower += mid * mid;
                    sidePower += side * side;
                }
                System.arraycopy(samples, 0, probe, probeLength, length);
                probeLength += length;
                if (probeLength == probe.length) startProcessing();
            }
            length = 0;
        }

        private void fillHop(int offset, int count) {
            System.arraycopy(samples, offset, hop, 0, count);
            Arrays.fill(hop, count, hop.length, (short) 0);
        }

        private void startProcessing() throws IOException {
            if (cancellation.isCancelled()) throw failure("cancelled");
            if (extension != null && extension.hasUsefulOutput() && !extension.hasBroadSpectrum()) {
                effects.add("bandwidth");
                extension = new BandwidthExtension(rate, channels);
            } else {
                extension = null;
            }
            if (noise.hasUsefulOutput()) {
                effects.add("noise");
                NoiseReduction trained = new NoiseReduction(rate, channels);
                trained.useProfileFrom(noise);
                noise = trained;
            } else {
                noise = null;
            }
            int probeFrames = probeLength / channels;
            if (probeFrames >= rate / 4
                    && midPower > 80.0 * probeFrames
                    && sidePower < .28 * midPower) {
                effects.add("space");
                space = new HeadphoneSpace(rate, channels);
            }
            if (effects.isEmpty()) throw failure("unchanged");
            outputChannels = space == null ? channels : 2;
            long estimatedBytes = durationMs * (2L * outputChannels * rate) / 1000;
            if (estimatedBytes > MAX_PCM_BYTES) throw failure("size");
            if (estimatedBytes + (32L << 20) > output.getUsableSpace()) throw failure("storage");
            file.seek(44);

            for (int offset = 0; offset < probeLength; offset += samples.length) {
                if (cancellation.isCancelled()) throw failure("cancelled");
                int count = Math.min(probeLength - offset, samples.length);
                System.arraycopy(probe, offset, samples, 0, count);
                process(count / channels);
            }
            probe = null;
        }

        private void process(int frames) throws IOException {
            if (extension != null) extension.process(samples, frames);
            if (noise == null) {
                writeFrames(samples, frames);
                return;
            }
            int count = frames * channels;
            for (int offset = 0; offset < count; offset += hop.length) {
                int used = Math.min(hop.length, count - offset);
                fillHop(offset, used);
                noise.advance(hop, denoised);
                writeFrames(denoised, previousFrames);
                previousFrames = used / channels;
            }
        }

        private void writeFrames(short[] pcm, int frames) throws IOException {
            if (frames == 0) return;
            if (space != null) {
                space.process(pcm, frames, stereo);
                pcm = stereo;
            }
            int count = frames * outputChannels;
            int bytes = count * 2;
            if (pcmBytes + bytes > MAX_PCM_BYTES) throw failure("size");
            if (count > encodedSamples.remaining()) writeBuffer();
            encodedSamples.put(pcm, 0, count);
            pcmBytes += bytes;
        }

        private void writeBuffer() throws IOException {
            file.write(encoded, 0, encodedSamples.position() * Short.BYTES);
            encodedSamples.clear();
        }

        Rendered finish() throws IOException {
            if (length > 0) flush();
            if (probe != null) startProcessing();
            if (noise != null) {
                Arrays.fill(hop, (short) 0);
                noise.advance(hop, denoised);
                writeFrames(denoised, previousFrames);
            }
            if (pcmBytes == 0) throw failure("decode");
            writeBuffer();
            ByteBuffer header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
            header.putInt(0x46464952).putInt(36 + pcmBytes).putInt(0x45564157);
            header.putInt(0x20746D66).putInt(16).putShort((short) 1);
            header.putShort((short) outputChannels).putInt(rate).putInt(rate * outputChannels * 2);
            header.putShort((short) (outputChannels * 2)).putShort((short) 16);
            header.putInt(0x61746164).putInt(pcmBytes);
            file.seek(0);
            file.write(header.array());
            return new Rendered(output, effects, 1000L * pcmBytes / (2L * outputChannels * rate));
        }
    }
}
