"""Original ranger skirmish cue: active strings, short woodwind calls, field drums.

Render a new audition without replacing any earlier recordings or game playback.
"""
import compose_bgm as base
from compose_focused_battle import render_cue

BPM, BARS = 126, 32
# GM program, channel volume, pan: bowed strings, soft backing strings,
# cello, flute, restrained timpani, acoustic guitar, drums.
PARTS = {0: (48, 95, 43), 1: (48, 43, 85), 2: (42, 83, 61),
         3: (73, 77, 70), 4: (47, 56, 62), 5: (24, 53, 83), 9: (0, 75, 64)}


def compose():
    notes = []

    def note(ch, n, beat, duration, velocity):
        pitch = base.pitch(n) if isinstance(n, str) else n
        assert 0 <= beat < BARS * 4 and beat + duration <= BARS * 4
        notes.append((ch, pitch, beat, duration, velocity))

    # D minor with a brief Dorian lift. No descending lament progression.
    chords = [ ('D3', 'D4 F4 A4'), ('D3', 'D4 F4 A4'),
               ('C3', 'C4 E4 G4'), ('G2', 'D4 G4 B4'),
               ('D3', 'D4 F4 A4'), ('F3', 'C4 F4 A4'),
               ('G2', 'D4 G4 Bb4'), ('A2', 'C#4 E4 A4') ]
    # A compact call-and-response hook. No scalar runs or sixteenth-note lead.
    theme = [
        'D5:1 A4:0.5 D5:1 -:1.5',
        'E5:1 F5:1 E5:0.5 D5:1 -:0.5',
        'G5:1 E5:1 D5:1 -:1',
        'B4:1 D5:1 G5:1 -:1',
        'A5:1 F5:0.5 E5:0.5 D5:1 -:1',
        'F5:1 A5:1 G5:1 -:1',
        'G5:1 F5:1 D5:1 -:1',
        'E5:1 C#5:1 A4:1 -:1',
    ]
    for bar in range(BARS):
        at, section = bar * 4, bar // 8
        root, voicing = chords[bar % 8]
        chord = base.pitches(voicing)
        r = base.pitch(root)
        level = [0.91, 1.0, 0.86, 1.04][section]
        # Low, tight repeated bow strokes supply motion without a busy melody.
        # Rest on the final eighth of each bar to keep attacks from becoming a wash.
        for j, off in enumerate([0, .5, 1, 1.5, 2, 2.5, 3]):
            if section == 2 and off in (1.5, 2.5):
                continue
            pitch = r + 12 if j in (0, 2, 4, 6) else chord[2] - 12
            vel = [74, 47, 59, 46, 70, 48, 60][j]
            note(0, pitch, at + off, .34, round(vel * level))
        # The bass stays grounded rather than walking or alternating in an oom-pah.
        for off, dur, vel in [(0, 1.7, 66), (2, 1.65, 59)]:
            note(2, r - (12 if r >= 48 else 0), at + off, dur, round(vel * level))
        for pitch in chord[:2]:
            note(1, pitch, at, 3.65, round(43 * level))
        # Dry plucked accents blend with the bow strokes; never a strummed rhythm.
        for off in (0, 2):
            for pitch in (chord[0], chord[2]):
                note(5, pitch, at + off, .65, round(46 * level))

        # Field-drum cadence: neither club kick pattern nor snare backbeat.
        note(9, 36, at, .15, round(76 * level))
        note(9, 41, at + 2, .2, round(61 * level))
        if bar % 2 == 1:
            note(9, 45, at + 3, .16, round(50 * level))
            note(9, 41, at + 3.5, .18, round(55 * level))
        if bar % 8 == 6:
            note(9, 38, at + 3, .14, 43)
        if bar % 8 == 0:
            note(4, r, at, .9, round(55 * level))
            note(9, 49, at, .3, 34)

        # Four-bar calls alternate with spaces for arrows and impacts.
        active = (section == 0 and bar % 8 < 4) or section == 1 or section == 3
        if active:
            for off, dur, pitch in base.phrase(theme[bar % 8]):
                note(3, pitch, at + off, dur * .82, round((69 if off == 0 else 59) * level))
        elif section == 2 and bar % 8 in (2, 3, 6, 7):
            # Quiet lower-register responses keep the middle moving, not mournful.
            line = 'A4:1 D5:1 -:2' if bar % 2 == 0 else 'E5:1 D5:1 -:2'
            for off, dur, pitch in base.phrase(line):
                note(3, pitch, at + off, dur * .72, 52)
    return notes


if __name__ == '__main__':
    render_cue(compose(), output=base.GAME / 'battle_v4',
               preview=base.PREVIEW / 'battle_v4', work=base.ROOT / '.tools/music-v4',
               identifier='E_ranger_skirmish', title='林间交锋', bpm=BPM, bars=BARS,
               parts=PARTS, revision=4, target_lufs=-17,
               style='短弦推进、木管短句应答、轻战鼓；游侠交战的敏捷感与紧张感')
