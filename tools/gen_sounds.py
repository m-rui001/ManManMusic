import math, struct, wave, os

RATE = 44100

def tone(freq, ms, amp=0.22, fade_ms=8):
    n = int(RATE * ms / 1000)
    fade = int(RATE * fade_ms / 1000)
    out = []
    for i in range(n):
        env = 1.0
        if i < fade:
            env = i / fade
        elif i > n - fade:
            env = max(0.0, (n - i) / fade)
        # 加一点二次谐波，听起来更像「叮」而不是纯正弦
        s = math.sin(2 * math.pi * freq * i / RATE) * 0.8 + math.sin(4 * math.pi * freq * i / RATE) * 0.2
        out.append(s * amp * env)
    return out

def silence(ms):
    return [0.0] * int(RATE * ms / 1000)

def write(path, samples):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = b"".join(struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples)
        w.writeframes(frames)

# 加入：两个上行的短音
join = tone(988, 55) + silence(18) + tone(1319, 85)
# 离开：两个下行的短音，更轻一点
leave = tone(784, 55, amp=0.18) + silence(18) + tone(523, 95, amp=0.18)

write("assets/sounds/party_join.wav", join)
write("assets/sounds/party_leave.wav", leave)
print("ok", os.path.getsize("assets/sounds/party_join.wav"), os.path.getsize("assets/sounds/party_leave.wav"))
