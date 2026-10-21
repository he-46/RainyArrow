"""A new, sparse combat cue: held strings, low pulses and restrained percussion.

Uses the same local FluidSynth/SoundFont setup as compose_battle_variants.py.
The earlier battle melody is deliberately not reused. No runtime music changes.
"""
import hashlib
import json
import math
from pathlib import Path
import shutil
import struct
import subprocess
import wave

import numpy as np
import compose_bgm as base
from compose_battle_variants import ENGINE, SOUNDFONT

OUT = base.GAME / 'battle_v3'
PRE = base.PREVIEW / 'battle_v3'
WORK = base.ROOT / '.tools/music-v3'
ID = 'D_focused_battle'
TITLE = '临阵'
BPM, BARS = 96, 32
TEMPO = round(60000000 / BPM)
FRAMES = round(BARS * 4 * TEMPO / 1000000 * base.SR)
# GM: cello, string ensemble, contrabass, French horn, timpani, percussion.
PARTS = {0: (42, 80, 51), 1: (48, 61, 78), 2: (43, 68, 64),
         3: (60, 52, 58), 4: (47, 62, 64), 9: (0, 61, 64)}


def compose():
    notes = []

    def note(ch, pitch, beat, length, velocity):
        n = base.pitch(pitch) if isinstance(pitch, str) else pitch
        assert beat >= 0 and beat + length <= BARS * 4
        notes.append((ch, n, beat, length, velocity))

    # Two bars per harmony; smooth, dark voice leading instead of arpeggios.
    harmony = [('D2', 'A3 D4 F4'), ('D2', 'Bb3 D4 F4'),
               ('G2', 'Bb3 D4 G4'), ('A2', 'A3 D4 E4'),
               ('D2', 'A3 D4 F4'), ('Bb1', 'Bb3 D4 F4'),
               ('G2', 'Bb3 D4 G4'), ('A2', 'A3 C#4 E4')]
    for bar in range(BARS):
        section = bar // 8
        level = [0.83, 0.96, 0.78, 1.0][section]
        root, chord = harmony[(bar // 2) % len(harmony)]
        at = bar * 4
        # Consistent low half-note pulse; no offbeats, walking bass or fills.
        for offset, velocity in [(0, 67), (2, 57)]:
            note(0, base.pitch(root) + 12, at + offset, 1.8, round(velocity * level))
        if bar % 2 == 0:
            note(2, root, at, 7.7, round(55 * level))
            for n in base.pitches(chord):
                note(1, n, at, 7.65, round(48 * level))
            note(4, base.pitch(root) + (12 if base.pitch(root) < 38 else 0),
                 at, 1.7, round(50 * level))
        # A single grounded downbeat, with an occasional distant low tom.
        note(9, 36, at, 0.2, round(63 * level))
        if bar % 2 == 1 and section != 2:
            note(9, 41, at + 2, 0.3, round(43 * level))

    # Short, low-register calls with long rests; only 11 lead notes in 80 s.
    for beat, n, length, velocity in [
        (16, 'D4', 3.6, 54), (20, 'C4', 3.5, 48), (24, 'A3', 5.6, 46),
        (40, 'D4', 5.6, 56), (46, 'F4', 1.8, 49), (48, 'E4', 5.5, 51),
        (88, 'A3', 5.5, 42),
        (104, 'D4', 5.6, 56), (110, 'F4', 1.8, 49),
        (112, 'E4', 3.6, 52), (116, 'D4', 3.5, 46),
    ]:
        note(3, n, beat, length, velocity)
    return notes


def write_midi(path, notes, cycles=1, *, title=TITLE, tempo=TEMPO, bars=BARS, parts=PARTS):
    name = title.encode('utf-8')
    events = [(0, b'\xff\x03' + base.vlq(len(name)) + name),
              (0, b'\xff\x51\x03' + tempo.to_bytes(3, 'big')),
              (0, b'\xff\x58\x04\x04\x02\x18\x08')]
    for ch, (program, volume, pan) in parts.items():
        events.append((0, bytes([0xc0 | ch, program])))
        for cc, value in [(7, volume), (10, pan), (91, 0), (93, 0)]:
            events.append((0, bytes([0xb0 | ch, cc, value])))
    for cycle in range(cycles):
        for ch, n, start, length, velocity in notes:
            tick = round((start + cycle * bars * 4) * 480)
            events.extend([(tick, bytes([0x90 | ch, n, velocity])),
                           (tick + round(length * 480), bytes([0x80 | ch, n, 0]))])
    events.sort(key=lambda e: (e[0], 0 if e[1][0] & 0xf0 == 0x80 else 1))
    data, last = bytearray(), 0
    for tick, event in events:
        data += base.vlq(tick - last) + event
        last = tick
    data += base.vlq(bars * 4 * 480 * cycles - last) + b'\xff\x2f\x00'
    path.write_bytes(b'MThd' + struct.pack('>IHHH', 6, 0, 1, 480)
                     + b'MTrk' + struct.pack('>I', len(data)) + data)


def render_cue(notes, *, output=OUT, preview=PRE, work=WORK, identifier=ID,
               title=TITLE, bpm=BPM, bars=BARS, parts=PARTS, revision=3,
               target_lufs=-19,
               style='低弦稳定脉冲、长音弦乐、稀疏圆号与低鼓；克制、严肃的战斗底乐'):
    # Local aliases let subsequent cues share the proven rendering/check pipeline.
    OUT, PRE, WORK = output, preview, work
    ID, TITLE, BPM, BARS = identifier, title, bpm, bars
    tempo = round(60000000 / bpm)
    FRAMES = round(bars * 4 * tempo / 1000000 * base.SR)
    for folder in (OUT, PRE, WORK):
        folder.mkdir(parents=True, exist_ok=True)
    accepted = [p for folder in (base.GAME, base.PREVIEW) for p in folder.iterdir()
                if p.is_file() and p.name.startswith(('01_', '03_'))]
    hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in accepted}
    midi_options = dict(title=title, tempo=tempo, bars=bars, parts=parts)
    write_midi(OUT / (ID + '.mid'), notes, **midi_options)
    midi = WORK / 'three_loops.mid'
    write_midi(midi, notes, 3, **midi_options)
    raw = WORK / 'render.wav'
    print(f'Rendering {identifier}: {FRAMES / base.SR:.2f} seconds, {bpm} BPM.', flush=True)
    proc = subprocess.run([str(ENGINE), '-ni', '-r', str(base.SR), '-g', '0.35',
                           '-C', '0', '-R', '0', '-o', 'synth.polyphony=256',
                           '-o', 'synth.cpu-cores=1', '-O', 'float', '-T', 'wav',
                           '-F', str(raw), str(SOUNDFONT), str(midi)],
                          capture_output=True, text=True, encoding='utf-8', errors='replace')
    (WORK / 'render.log').write_text(proc.stdout + proc.stderr, encoding='utf-8')
    if proc.returncode:
        raise RuntimeError(proc.stdout + proc.stderr)
    pcm = WORK / 'render.f32'
    base.run_ffmpeg(['-y', '-i', str(raw), '-f', 'f32le', '-c:a', 'pcm_f32le', str(pcm)])
    full = np.fromfile(pcm, dtype='<f4').reshape(-1, 2)
    mix = full[FRAMES:FRAMES * 2].copy()
    assert len(mix) == FRAMES
    # Match the loop start to the next pass's real continuation before blending.
    width = round(.045 * base.SR)
    fade = np.sin(np.linspace(0, math.pi / 2, width, dtype=np.float32))[:, None] ** 2
    mix[:width] = full[FRAMES * 2:FRAMES * 2 + width] * (1 - fade) + mix[:width] * fade
    mix -= np.mean(mix, axis=0)
    dry = mix.copy()
    for delay, amount in [(.037, .07), (.071, .06), (.113, .045), (.181, .035), (.277, .025)]:
        mix += np.roll(dry[:, ::-1], round(delay * base.SR), axis=0) * amount
    mix *= 10 ** (-3 / 20) / max(float(np.max(np.abs(mix))), 1e-9)
    temp = WORK / 'measure.wav'
    base.write_wav(temp, mix)
    meter = base.loudness(temp)
    gain = min(target_lufs - float(meter['input_i']), -1.5 - float(meter['input_tp']))
    mix *= 10 ** (gain / 20)
    master = PRE / (ID + '.wav')
    base.write_wav(master, mix)
    tags = ['-metadata', 'title=' + TITLE, '-metadata', 'artist=RainyArrow / original composition']
    ogg = OUT / (ID + '.ogg')
    base.run_ffmpeg(['-y', '-i', str(master), '-c:a', 'libvorbis', '-q:a', '6', *tags,
                     '-metadata', 'LOOPSTART=0', '-metadata', f'LOOPEND={FRAMES}', str(ogg)])
    base.run_ffmpeg(['-y', '-i', str(master), '-c:a', 'libmp3lame', '-b:a', '192k',
                     *tags, str(PRE / (ID + '.mp3'))])
    decoded = WORK / 'decoded.wav'
    base.run_ffmpeg(['-y', '-i', str(ogg), '-c:a', 'pcm_s16le', str(decoded)])
    with wave.open(str(decoded), 'rb') as f:
        assert f.getnchannels() == 2 and f.getframerate() == base.SR
        assert abs(f.getnframes() - FRAMES) <= 2
        samples = np.frombuffer(f.readframes(f.getnframes()), '<i2').reshape(-1, 2).astype(np.float32) / 32768
    peak = float(np.max(np.abs(samples)))
    seam = float(np.max(np.abs(samples[0] - samples[-1])))
    delta = float(np.percentile(np.abs(np.diff(samples, axis=0)), 99.9))
    assert peak < .99 and not (seam > .025 and seam > delta * 2), (peak, seam, delta)
    meter = base.loudness(ogg)
    track = dict(id=ID, title=TITLE, file=ogg.name, bpm=BPM, bars=BARS,
                 style=style,
                 duration_seconds=FRAMES / base.SR, loop=True, loop_start=0, loop_end=FRAMES,
                 integrated_lufs=float(meter['input_i']), true_peak_dbtp=float(meter['input_tp']),
                 loop_boundary_delta=seam, sample_delta_p999=delta,
                 notes=len(notes), lead_notes=sum(n[0] == 3 for n in notes),
                 source_theme='new original composition', renderer='FluidSynth 2.6.1',
                 soundfont='GeneralUser GS 2.0.3')
    for path, expected in hashes.items():
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == expected
    catalog = dict(revision=revision, accepted_original_tracks=['01_menu_moonlit_bow', '03_ref_campfire_letters'],
                   soundfont_sha256=hashlib.sha256(SOUNDFONT.read_bytes()).hexdigest(), tracks=[track])
    (OUT / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding='utf-8')
    catalog['preserved_files_sha256'] = hashes
    (PRE / 'validation.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding='utf-8')
    shutil.copyfile(base.ROOT / '.tools/soundfonts/GeneralUser-GS-LICENSE.txt', OUT / 'GeneralUser-GS-LICENSE.txt')
    print(json.dumps(track, ensure_ascii=False), flush=True)
    print(f'Accepted originals unchanged: {len(hashes)} files.', flush=True)


if __name__ == '__main__':
    render_cue(compose())
