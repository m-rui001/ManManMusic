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

final class AudioRestoration {
    private static final int MAX_PCM_BYTES = 384 * 1024 * 1024;

    static File render(File input, File directory) throws IOException {
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
            decode(input, output);
            complete = true;
            return output;
        } finally {
            if (!complete) output.delete();
        }
    }

    private static void decode(File input, File output) throws IOException {
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
            long bytesPerSecond = 2L * channels * rate;
            if (format.containsKey(MediaFormat.KEY_DURATION)) {
                long estimatedBytes =
                    format.getLong(MediaFormat.KEY_DURATION) / 1000 * bytesPerSecond / 1000;
                if (estimatedBytes > MAX_PCM_BYTES) throw failure("size");
                if (estimatedBytes + (32L << 20) > output.getUsableSpace()) {
                    throw failure("storage");
                }
            }
            if (Build.VERSION.SDK_INT >= 24) {
                format.setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT);
            }
            decoder = MediaCodec.createDecoderByType(mime);
            decoder.configure(format, null, null, 0);
            decoder.start();
            WavWriter writer = new WavWriter(wav, rate, channels);
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            boolean inputEnded = false;
            boolean outputEnded = false;
            long deadline = SystemClock.elapsedRealtime() + 180_000;
            while (!outputEnded) {
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
            writer.finish();
        } finally {
            try {
                if (decoder != null) decoder.release();
            } finally {
                extractor.release();
            }
        }
    }

    private static MediaFormat selectTrack(MediaExtractor extractor) throws IOException {
        for (int index = 0; index < extractor.getTrackCount(); index++) {
            MediaFormat format = extractor.getTrackFormat(index);
            String mime = format.getString(MediaFormat.KEY_MIME);
            if ("audio/mp4a-latm".equals(mime) || "audio/mpeg".equals(mime)) {
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
        private final int rate;
        private final int channels;
        private final BandwidthExtension extension;
        private final short[] samples;
        private final ByteBuffer encoded;
        private int length;
        private int pcmBytes;

        WavWriter(RandomAccessFile file, int rate, int channels) throws IOException {
            this.file = file;
            this.rate = rate;
            this.channels = channels;
            extension = new BandwidthExtension(rate, channels);
            samples = new short[BandwidthExtension.FRAMES * channels];
            encoded = ByteBuffer.allocate(samples.length * 2).order(ByteOrder.LITTLE_ENDIAN);
            file.seek(44);
        }

        void write(ByteBuffer decoded) throws IOException {
            if ((decoded.remaining() & 1) != 0) throw failure("decode");
            while (decoded.hasRemaining()) {
                samples[length++] = decoded.getShort();
                if (length == samples.length) flush();
            }
        }

        private void flush() throws IOException {
            if (length % channels != 0) throw failure("decode");
            int bytes = length * 2;
            if (pcmBytes + bytes > MAX_PCM_BYTES) throw failure("size");
            extension.process(samples, length / channels);
            encoded.clear();
            for (int i = 0; i < length; i++) encoded.putShort(samples[i]);
            file.write(encoded.array(), 0, bytes);
            pcmBytes += bytes;
            length = 0;
        }

        void finish() throws IOException {
            if (length > 0) flush();
            if (!extension.hasUsefulOutput()) throw failure("bandwidth");
            ByteBuffer header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN);
            header.putInt(0x46464952).putInt(36 + pcmBytes).putInt(0x45564157);
            header.putInt(0x20746D66).putInt(16).putShort((short) 1);
            header.putShort((short) channels).putInt(rate).putInt(rate * channels * 2);
            header.putShort((short) (channels * 2)).putShort((short) 16);
            header.putInt(0x61746164).putInt(pcmBytes);
            file.seek(0);
            file.write(header.array());
        }
    }
}
