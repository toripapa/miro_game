import wave
import math
import struct
import os

sample_rate = 44100
duration = 8.0 # seconds
num_samples = int(sample_rate * duration)

if not os.path.exists('assets/audio'):
    os.makedirs('assets/audio', exist_key=True)

wavef = wave.open('assets/audio/monster_bgm.wav', 'w')
wavef.setnchannels(2) # stereo
wavef.setsampwidth(2) # 16-bit
wavef.setframerate(sample_rate)

# 무섭고 긴장감을 주는 낮은 톤과 불협화음
root = 55.0 # Low A
freqs = [root, root * 1.5, root * 1.12246, root * 2.5] # Minor second dissonance & harsh overtone

for i in range(num_samples):
    t = float(i) / sample_rate

    # 빠른 심장박동 같은 진동(LFO)을 적용하여 긴장감 생성
    lfo_t = 2.0 * math.pi * t * 2.0 # faster oscillation

    valL = 0.0
    valR = 0.0

    for idx, f in enumerate(freqs):
        lfo_pitch = math.sin(lfo_t * (idx + 0.5)) * 1.5
        lfo_vol = 0.5 + 0.5 * math.sin(lfo_t * (idx * 1.5 + 2))

        phase = 2.0 * math.pi * (f + lfo_pitch) * t

        # 톱니파(sawtooth-like)와 사인파 배합으로 날카로운 소리 연출
        s = math.sin(phase) + math.sin(phase * 1.5) * 0.4

        valL += s * lfo_vol * 0.2 * (0.8 if idx % 2 == 0 else 0.4)
        valR += s * lfo_vol * 0.2 * (0.4 if idx % 2 == 0 else 0.8)

    # 16비트 오디오 변환
    L = int(max(-1.0, min(1.0, valL)) * 32767.0)
    R = int(max(-1.0, min(1.0, valR)) * 32767.0)

    wavef.writeframesraw(struct.pack('<hh', L, R))

wavef.close()
print("무서운 배경음악 생성이 완료되었습니다: assets/audio/monster_bgm.wav")
