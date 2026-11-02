"""建立可重現的節奏測試音訊，不使用下載的歌曲。輸出至被忽略的 build/。"""
from pathlib import Path
import subprocess
import wave
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "music_tests"


def create(bpm, phase=0.23, name=None, seconds=20):
    rate = 44100
    rng = np.random.default_rng(73)
    t = np.arange(int(rate * seconds)) / rate
    sound = 0.015 * (np.sin(2 * np.pi * 220 * t) + np.sin(2 * np.pi * 330 * t))
    for index, at in enumerate(np.arange(phase, seconds - 0.2, 60 / bpm)):
        start = int(at * rate)
        x = np.arange(int(rate * 0.16)) / rate
        kick = np.sin(2 * np.pi * (85 * x - 130 * x * x)) * np.exp(-x * 32)
        sound[start:start + len(x)] += kick * (0.75 if index % 4 == 0 else 0.6)
        hat_start = int((at + 30 / bpm) * rate)
        hat = rng.normal(0, 0.012, int(rate * 0.035)) * np.exp(-np.arange(int(rate * 0.035)) / rate * 90)
        if hat_start + len(hat) < len(sound):
            sound[hat_start:hat_start + len(hat)] += hat
    pcm = (np.clip(sound, -1, 1) * 32767).astype('<i2')
    path = OUT / (name or f"beat_{bpm}.wav")
    with wave.open(str(path), 'wb') as file:
        file.setparams((1, 2, rate, len(pcm), 'NONE', 'not compressed'))
        file.writeframes(pcm.tobytes())
    return path


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    (ROOT / "build" / ".gdignore").touch()
    for bpm in (65, 90, 120, 150, 173.5, 200):
        create(bpm)
    create(120, 2.23, "intro_120.wav")
    with wave.open(str(OUT / 'silence.wav'), 'wb') as file:
        file.setparams((1, 2, 44100, 441000, 'NONE', 'not compressed'))
        file.writeframes(bytes(441000 * 2))
    (OUT / 'invalid.mp3').write_bytes(b'not an audio file')
    import imageio_ffmpeg
    executable = imageio_ffmpeg.get_ffmpeg_exe()
    for extension in ('mp3', 'ogg'):
        subprocess.run([executable, '-v', 'error', '-y', '-i', str(OUT / 'beat_150.wav'),
                        str(OUT / f'beat_150.{extension}')], check=True)
    print(OUT)
