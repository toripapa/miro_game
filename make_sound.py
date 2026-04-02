import wave
import math
import struct
import os

sample_rate = 44100
duration = 16.0 # seconds
num_samples = int(sample_rate * duration)

if not os.path.exists('assets/audio'):
    os.makedirs('assets/audio', exist_key=True)

wavef = wave.open('assets/audio/bgm.wav', 'w')
wavef.setnchannels(2) # stereo
wavef.setsampwidth(2) # 16-bit
wavef.setframerate(sample_rate)

# 은은하면서도 약간 긴장감을 주는 단조(마이너) 화음 드론 사운드
root = 110.0 # A2
freqs = [root, root * 1.5, root * 1.1892] # A, E, C (A minor 텍스처)

for i in range(num_samples):
    t = float(i) / sample_rate

    # 원활한 루핑을 위해 16초 주기의 LFO 사용
    lfo_t = 2.0 * math.pi * t / duration

    valL = 0.0
    valR = 0.0

    for idx, f in enumerate(freqs):
        # 느린 진동(LFO)을 적용하여 긴장감과 울림 생성
        lfo_pitch = math.sin(lfo_t * (idx + 1)) * 0.5
        lfo_vol = 0.5 + 0.5 * math.sin(lfo_t * (idx + 2))

        phase = 2.0 * math.pi * (f + lfo_pitch) * t

        # 사인파를 활용한 부드러운 소리
        s = math.sin(phase)

        # 좌우 채널에 다르게 분배해 공간감 형성
        valL += s * lfo_vol * 0.3 * (0.8 if idx % 2 == 0 else 0.4)
        valR += s * lfo_vol * 0.3 * (0.4 if idx % 2 == 0 else 0.8)

    # 16비트 오디오 변환
    L = int(max(-1.0, min(1.0, valL)) * 32767.0)
    R = int(max(-1.0, min(1.0, valR)) * 32767.0)

    wavef.writeframesraw(struct.pack('<hh', L, R))

wavef.close()
print("배경음악 생성이 완료되었습니다: assets/audio/bgm.wav")
