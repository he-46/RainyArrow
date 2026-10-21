"""Original RainyArrow BGM sketches, composed and synthesized without external samples.

Run with Python 3.12 + numpy + imageio-ffmpeg. Local optional dependencies are
loaded from .tools/music-deps. Outputs: game OGG, editable MIDI, WAV/MP3 auditions.
No player saves, game code, or network services are used by this renderer.
"""
from __future__ import annotations
import argparse
import json
import math
import re
import struct
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.tools' / 'music-deps'))
import imageio_ffmpeg

SR = 44100
GAME = ROOT / 'assets' / 'audio' / 'music'
PREVIEW = ROOT / 'artifacts' / 'bgm'
TAU = 2 * math.pi
SEMITONES = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
PROGRAMS = {'flute': 73, 'pluck': 24, 'bell': 10, 'strings': 48,
            'bass': 33, 'lead': 80, 'pad': 89, 'chip': 80}
CHANNELS = {name: i for i, name in enumerate(PROGRAMS)}


def pitch(name: str) -> int:
    match = re.fullmatch(r'([A-G])([#b]?)(-?\d+)', name)
    if not match:
        raise ValueError(name)
    letter, accidental, octave = match.groups()
    return (int(octave) + 1) * 12 + SEMITONES[letter] + {'': 0, '#': 1, 'b': -1}[accidental]


def pitches(text: str) -> list[int]:
    return [pitch(n) for n in text.split()]


def phrase(text: str) -> list[tuple[float, float, int]]:
    """A bar: note:beats; dash is a rest. Every supplied bar totals four beats."""
    notes = []
    cursor = 0.0
    for token in text.split():
        name, beats = token.split(':')
        duration = float(beats)
        if name != '-':
            notes.append((cursor, duration, pitch(name)))
        cursor += duration
    if abs(cursor - 4) > 1e-8:
        raise ValueError(f'Bar must total 4 beats: {text} = {cursor}')
    return notes


MENU_A = [
    'D5:1 F#5:.5 E5:.5 A4:1 -:.5 D5:.5',
    'F#5:1 A5:.5 F#5:.5 E5:1 D5:1',
    'B4:1 D5:1 E5:.5 D5:.5 B4:1',
    'A4:1 E5:.5 F#5:.5 E5:1 -:1',
    'D5:.5 E5:.5 F#5:1 A5:1 F#5:1',
    'E5:.5 D5:.5 B4:1 D5:1 F#5:1',
    'E5:1 G5:.5 F#5:.5 E5:.5 D5:.5 B4:1',
    'C#5:1 E5:1 A4:1 -:1',
]
MENU_B = [
    'G5:1 A5:.5 B5:.5 A5:1 G5:1',
    'F#5:1 D5:.5 F#5:.5 A5:1 F#5:1',
    'E5:1 G5:1 F#5:.5 E5:.5 D5:1',
    'E5:1 C#5:1 A4:1 -:1',
    'B4:.5 D5:.5 G5:1 A5:.5 G5:.5 E5:1',
    'F#5:1 E5:.5 D5:.5 A4:1 D5:1',
    'G5:1 F#5:.5 E5:.5 D5:1 B4:1',
    'C#5:1 E5:1 A4:1 -:1',
]
CAMP_A = [
    'E5:.75 G5:.25 A5:1 G5:.5 E5:.5 D5:1',
    'E5:1 C5:.5 D5:.5 E5:1 G5:1',
    'A5:1 G5:.5 E5:.5 D5:.75 E5:.25 C5:1',
    'D5:1 B4:1 G4:1 -:1',
    'C5:.5 E5:.5 G5:1 E5:1 D5:1',
    'C5:1 A4:.5 C5:.5 E5:.5 G5:.5 E5:1',
    'D5:1 F5:1 E5:.5 D5:.5 C5:1',
    'B4:1 D5:1 G4:1 -:1',
]
CAMP_B = [
    'A5:1 G5:.5 A5:.5 C6:1 A5:1',
    'G5:1 E5:.5 G5:.5 B5:1 G5:1',
    'F5:1 A5:.5 G5:.5 F5:1 E5:1',
    'D5:1 G5:1 B4:1 -:1',
    'A5:.5 G5:.5 F5:1 E5:.5 D5:.5 C5:1',
    'E5:1 G5:1 E5:1 C5:1',
    'D5:.5 E5:.5 F5:1 A5:.5 F5:.5 D5:1',
    'B4:1 D5:1 G4:1 -:1',
]
BATTLE_A = [
    'D5:.5 D5:.5 F5:.5 A5:.5 D6:1 C6:.5 A5:.5',
    'Bb5:1 A5:.5 G5:.5 F5:1 D5:.5 F5:.5',
    'A5:.75 C6:.25 A5:.5 G5:.5 F5:1 A5:1',
    'G5:.5 G5:.5 E5:.5 G5:.5 C6:1 G5:.5 E5:.5',
    'D5:.5 F5:.5 A5:1 G5:.5 F5:.5 E5:.5 D5:.5',
    'F5:.5 Bb5:.5 A5:1 G5:.5 F5:.5 D5:1',
    'A5:.5 C6:.5 D6:1 C6:.5 A5:.5 G5:1',
    'E5:.5 G5:.5 A5:1 C#6:.5 B5:.5 A5:1',
]
BATTLE_B = [
    'G5:1 Bb5:.5 A5:.5 G5:.5 F5:.5 D5:1',
    'F5:.5 G5:.5 Bb5:1 D6:1 Bb5:1',
    'A5:1 F5:.5 E5:.5 D5:1 A4:1',
    'E5:.5 A5:.5 C#6:1 B5:.5 A5:.5 E5:1',
    'G5:.5 A5:.5 Bb5:.5 D6:.5 C6:1 Bb5:1',
    'A5:.5 G5:.5 F5:1 D5:1 F5:1',
    'E5:.5 F5:.5 A5:1 D6:.5 C6:.5 A5:1',
    'G5:.5 E5:.5 C#5:1 E5:.5 G5:.5 A5:1',
]
BOSS_A = [
    'E5:.5 E5:.5 G5:.5 B5:.5 E6:1 D6:.5 B5:.5',
    'C6:.75 B5:.25 G5:.5 E5:.5 G5:1 B5:1',
    'A5:.5 C6:.5 B5:.5 A5:.5 G5:1 E5:1',
    'F#5:.5 B5:.5 D#6:1 C6:.5 B5:.5 F#5:1',
    'E5:.25 F#5:.25 G5:.5 B5:.5 E6:.5 D6:1 B5:1',
    'C6:.5 B5:.5 G5:1 E5:.5 G5:.5 C6:1',
    'A5:.5 B5:.5 C6:1 E6:1 C6:.5 A5:.5',
    'B5:1 F#5:.5 D#5:.5 B4:1 -:.5 B4:.5',
]
BOSS_B = [
    'C6:1 E6:.5 D6:.5 C6:1 B5:1',
    'A5:.5 C6:.5 E6:1 D6:.5 C6:.5 A5:1',
    'G5:.5 B5:.5 E6:1 B5:.5 A5:.5 G5:1',
    'F#5:1 D#5:.5 F#5:.5 B5:1 -:1',
    'C6:.5 B5:.5 G5:.5 E5:.5 C5:1 E5:1',
    'A5:.5 C6:.5 B5:.5 A5:.5 E5:1 A5:1',
    'G5:.5 F#5:.5 E5:1 B4:.5 E5:.5 G5:1',
    'F#5:.5 A5:.5 B5:1 D#6:1 B5:1',
]
CHIP_A = [
    'A5:.5 C6:.5 E6:.5 C6:.5 A5:.5 E5:.5 G5:.5 A5:.5',
    'F5:.5 A5:.5 C6:1 A5:.5 G5:.5 F5:1',
    'E5:.5 G5:.5 C6:.5 E6:.5 D6:1 C6:1',
    'B5:.5 D6:.5 G6:.5 D6:.5 B5:1 G5:1',
    'A5:.5 B5:.5 C6:1 E6:.5 D6:.5 C6:1',
    'F6:.5 E6:.5 C6:1 A5:.5 C6:.5 F5:1',
    'E5:.5 G5:.5 C6:1 G5:.5 E5:.5 D5:1',
    'B4:.5 E5:.5 G#5:.5 B5:.5 E6:1 B5:.5 G#5:.5',
]
CHIP_B = [
    'D6:1 C6:.5 A5:.5 F5:.5 A5:.5 D6:1',
    'C6:.5 A5:.5 F5:1 A5:.5 C6:.5 F6:1',
    'E6:1 C6:.5 B5:.5 A5:1 E5:1',
    'B5:.5 G#5:.5 E5:.5 G#5:.5 B5:1 E6:1',
    'F6:.5 E6:.5 D6:1 C6:.5 A5:.5 F5:1',
    'G5:.5 A5:.5 B5:1 D6:.5 B5:.5 G5:1',
    'A5:.5 C6:.5 E6:1 C6:.5 A5:.5 E5:1',
    'G#5:.5 B5:.5 E6:1 D6:.5 B5:.5 G#5:1',
]

# Deliberate chord voicings, separate bass roots, and composed A/B melodies.
TRACKS = [
    dict(id='01_menu_moonlit_bow', title='月下弓弦', role='主页面', bpm=80, bars=32, key='D major',
         style='竹笛、木质拨弦、柔和音垫；平静、有旋律记忆点', mood='menu', seed=4101,
         chords_a=['D3 F#3 A3 E4','B2 D3 F#3 A3','G2 B2 D3 A3','A2 C#3 E3 B3']*2,
         chords_b=['G2 B2 D3 A3','B2 D3 F#3 A3','E3 G3 B3 D4','A2 C#3 E3 B3','G2 B2 D3 A3','D3 F#3 A3 E4','E3 G3 B3 D4','A2 C#3 E3 G3'],
         melody_a=MENU_A, melody_b=MENU_B, sections='ABAA', lead='flute', lufs=-18),
    dict(id='02_battle_rain_of_arrows', title='万箭破晓', role='常规战斗', bpm=148, bars=48, key='D minor',
         style='合成弦乐短奏、英雄式主旋律、战鼓与低音；激昂、持续推进', mood='battle', seed=4102,
         chords_a=['D3 F3 A3 D4','Bb2 D3 F3 A3','F3 A3 C4 F4','C3 E3 G3 C4','D3 F3 A3 D4','Bb2 D3 F3 A3','F3 A3 C4 F4','A2 C#3 E3 G3'],
         chords_b=['G2 Bb2 D3 G3','Bb2 D3 F3 A3','D3 F3 A3 D4','A2 C#3 E3 G3','G2 Bb2 D3 G3','Bb2 D3 F3 A3','D3 F3 A3 D4','A2 C#3 E3 G3'],
         melody_a=BATTLE_A, melody_b=BATTLE_B, sections='AABABA', lead='lead', lufs=-16),
    dict(id='03_ref_campfire_letters', title='营火来信', role='参考：温暖营地／天赋页', bpm=92, bars=32, key='C major',
         style='轻拨弦、钟琴与木质敲击；温暖、轻快，偏休憩和成长', mood='camp', seed=4103,
         chords_a=['C3 E3 G3 B3','A2 C3 E3 G3','F2 A2 C3 E3','G2 B2 D3 A3']*2,
         chords_b=['F2 A2 C3 E3','C3 E3 G3 B3','D3 F3 A3 C4','G2 B2 D3 A3','F2 A2 C3 E3','C3 E3 G3 B3','D3 F3 A3 C4','G2 B2 D3 F3'],
         melody_a=CAMP_A, melody_b=CAMP_B, sections='ABAA', lead='pluck', lufs=-18),
    dict(id='04_ref_iron_target', title='铁弦压境', role='参考：Boss战', bpm=164, bars=48, key='E minor',
         style='低音脉冲、密集短弦、重鼓与紧张主题；更强压迫感', mood='boss', seed=4104,
         chords_a=['E2 G2 B2 E3','C3 E3 G3 B3','A2 C3 E3 G3','B2 D#3 F#3 A3']*2,
         chords_b=['C3 E3 G3 B3','A2 C3 E3 G3','E3 G3 B3 D4','B2 D#3 F#3 A3']*2,
         melody_a=BOSS_A, melody_b=BOSS_B, sections='AABABA', lead='lead', lufs=-16),
    dict(id='05_ref_pixel_arrowdance', title='像素箭舞', role='参考：街机风战斗', bpm=136, bars=48, key='A minor',
         style='脉冲波主旋律、圆润低音、琶音与噪声鼓；明快复古', mood='chip', seed=4105,
         chords_a=['A2 C3 E3 A3','F2 A2 C3 E3','C3 E3 G3 C4','G2 B2 D3 G3','A2 C3 E3 A3','F2 A2 C3 E3','C3 E3 G3 C4','E3 G#3 B3 D4'],
         chords_b=['D3 F3 A3 C4','F2 A2 C3 E3','A2 C3 E3 A3','E3 G#3 B3 D4','F2 A2 C3 E3','G2 B2 D3 G3','A2 C3 E3 A3','E3 G#3 B3 D4'],
         melody_a=CHIP_A, melody_b=CHIP_B, sections='AABABA', lead='chip', lufs=-17),
]


class Song:
    def __init__(self, spec):
        self.spec = spec
        self.spb = 60 / spec['bpm']
        self.frames = round(spec['bars'] * 4 * self.spb * SR)
        self.rng = np.random.default_rng(spec['seed'])
        self.music = np.zeros((self.frames, 2), np.float32)
        self.drums = np.zeros_like(self.music)
        self.air = np.zeros_like(self.music)
        self.events = []
        self.cache = {}

    def add(self, bus, samples, beat, pan=0):
        pos = round(beat * self.spb * SR) % self.frames
        n = len(samples)
        gains = (math.sqrt((1-pan)/2), math.sqrt((1+pan)/2))
        first = min(n, self.frames-pos)
        for c, gain in enumerate(gains):
            bus[pos:pos+first, c] += samples[:first] * gain
            if first < n:
                bus[:n-first, c] += samples[first:] * gain

    def note(self, voice, midi, beat, duration, gain=.2, pan=0, wet=False):
        sec = duration*self.spb
        release = {'flute': .16, 'pluck': .22, 'bell': .8, 'strings': .10,
                   'bass': .065, 'lead': .12, 'pad': .55, 'chip': .035}[voice]
        key = (voice, midi, round(sec, 6))
        if key not in self.cache:
            t = np.arange(round((sec+release)*SR), dtype=np.float32)/SR
            f = 440 * 2 ** ((midi-69)/12)
            vibrato = .0025*np.sin(TAU*5.1*t)*np.minimum(t/.3,1)
            phase = TAU*f*t + (f*.0025/5.1)*(1-np.cos(TAU*5.1*t))*np.minimum(t/.3,1)
            if voice == 'flute':
                signal = np.sin(phase)+.20*np.sin(phase*2)+.055*np.sin(phase*3)
                noise = self.rng.normal(0, 1, len(t)).astype(np.float32)
                signal += .018*(noise-np.roll(noise,1))
                env = np.minimum(t/.075,1)*(.90+.10*np.sin(TAU*3.2*t))
            elif voice in ('pluck','bell'):
                ratios = [1,2,3,4,5] if voice=='pluck' else [1,2,2.756,4.03,5.41]
                amps = [1,.34,.17,.08,.035] if voice=='pluck' else [1,.28,.13,.07,.025]
                signal = sum(a*np.sin(TAU*f*r*t)*np.exp(-t*(1.3+i*.7)) for i,(r,a) in enumerate(zip(ratios,amps)))
                env = np.minimum(t/.006,1)*np.exp(-t*(2.5 if voice=='pluck' else .9))
            elif voice == 'bass':
                phase = TAU*f*t
                signal = np.sin(phase)+.22*np.sin(2*phase)+.07*np.sin(3*phase)
                env = np.minimum(t/.012,1)*(.65+.35*np.exp(-t*7))
            elif voice in ('strings','pad'):
                signal = np.zeros_like(t)
                for detune in (-.0018,.0015):
                    for harmonic in range(1,9 if voice=='strings' else 5):
                        signal += np.sin(TAU*f*(1+detune)*harmonic*t+harmonic*.12)/harmonic**1.6*.5
                env = np.minimum(t/(.022 if voice=='strings' else .22),1)
                if voice=='strings': env *= .55+.45*np.exp(-t*11)
                else: env *= .9+.1*np.sin(TAU*.7*t)
            elif voice == 'lead':
                signal = .66*np.sin(phase)+.19*np.sin(2*phase)+.14*np.sin(3*phase)+.07*np.sin(5*phase)
                signal += .12*np.sin(TAU*f*1.003*t)
                env = np.minimum(t/.018,1)*(.8+.2*np.exp(-t*8))
            else: # Band-limited pulse, no harsh naive square-wave aliasing.
                signal = np.zeros_like(t)
                for harmonic in range(1,min(15,int(SR*.43/f)),2):
                    signal += np.sin(phase*harmonic)/harmonic**1.35
                env = np.minimum(t/.004,1)*(.65+.35*np.exp(-t*10))
            env *= np.clip((sec+release-t)/release,0,1)
            signal = (signal*env).astype(np.float32)
            self.cache[key] = signal
        self.add(self.air if wet else self.music, self.cache[key]*gain, beat, pan)
        self.events.append((voice, midi, beat, duration, max(30,min(112,round(gain*220+30)))))

    def drum(self, kind, beat, gain=.2, pan=0):
        key=('drum',kind)
        if key not in self.cache:
            length={'kick':.32,'snare':.23,'hat':.065,'open':.23,'tom':.32,'wood':.08,'shaker':.055,'crash':1.2}[kind]
            t=np.arange(round(length*SR),dtype=np.float32)/SR
            noise=self.rng.normal(0,1,len(t)).astype(np.float32)
            high=(noise-np.roll(noise,1))*.5
            if kind=='kick':
                phase=TAU*(48*t+100*.018*(1-np.exp(-t/.018)))
                y=np.sin(phase)*np.exp(-t*15)+.10*noise*np.exp(-t*250)
            elif kind=='snare':
                y=.42*noise*np.exp(-t*26)+.45*np.sin(TAU*185*t)*np.exp(-t*30)+.12*np.sin(TAU*320*t)*np.exp(-t*40)
            elif kind=='tom':
                y=np.sin(TAU*(87*t+75*.03*(1-np.exp(-t/.03))))*np.exp(-t*12)+.04*noise*np.exp(-t*35)
            elif kind=='wood':
                y=(np.sin(TAU*830*t)+.5*np.sin(TAU*1230*t))*np.exp(-t*85)
            else:
                y=high*np.exp(-t*({'hat':85,'open':20,'shaker':65,'crash':5}[kind]))
                y += .06*(np.sin(TAU*4300*t)+np.sin(TAU*6173*t))*np.exp(-t*18)
            y*=np.minimum(t/.0015,1)*np.minimum((length-t)/.006,1)
            self.cache[key]=y.astype(np.float32)
        self.add(self.drums,self.cache[key]*gain,beat,pan)
        midi={'kick':36,'snare':38,'hat':42,'open':46,'tom':45,'wood':76,'shaker':70,'crash':49}[kind]
        self.events.append(('drums',midi,beat,.12,max(30,min(115,round(gain*220+30)))))

    def arrange(self):
        spec=self.spec
        calm=spec['mood'] in ('menu','camp')
        for bar in range(spec['bars']):
            section=bar//8
            form=spec['sections'][section]
            chord=pitches(spec['chords_a' if form=='A' else 'chords_b'][bar%8])
            root=chord[0]
            at=bar*4
            intensity=[.74,.90,1.0,.80,1.03,1.08][section] if not calm else [.70,.85,.73,.90][section]
            bridge=not calm and section==3
            if bridge: intensity=.62
            # Long harmony has circular release tails; it never fades to silence at a loop boundary.
            for j,n in enumerate(chord):
                self.note('pad', n+12, at, 3.85,.038*intensity if calm else .027*intensity, (j-1.5)*.37,True)
            if calm:
                self.note('bass',root-12,at,2.5,.16*intensity,-.05)
                if bar%2: self.note('bass',root-5,at+3,.8,.105*intensity,.02)
                pattern=[0,2,1,3,2,1,3,2]
                for j,k in enumerate(pattern):
                    off=j*.5 + (.035 if spec['mood']=='camp' and j%2 else 0)
                    self.note('pluck',chord[k]+12,at+off,.65,.11*intensity*(.8 if j%2 else 1),-.42 if j%2==0 else .38,True)
                if spec['mood']=='camp':
                    for off in (0,2): self.drum('wood',at+off,.09*intensity,-.25)
                    for off in (.5,1.5,2.5,3.5): self.drum('shaker',at+off,.085*intensity,.35)
                elif section>0:
                    for off in (1.5,3.5): self.drum('shaker',at+off,.045*intensity,.45)
            else:
                bass_note=root-12 if root>=45 else root
                bass_rhythm=[0,.75,1.5,2,2.75,3.5] if spec['mood']!='chip' else [0,.5,1,1.5,2,2.5,3,3.5]
                for j,off in enumerate(bass_rhythm):
                    self.note('bass',bass_note+(12 if j%4==3 else 0),at+off,.33,.24*intensity,0)
                if spec['mood']=='chip':
                    for j in range(16):
                        self.note('chip',chord[[0,2,1,3][j%4]]+12,at+j*.25,.12,.055*intensity,-.38 if j%2 else .38)
                else:
                    offsets=[0,.5,1,1.5,2,2.5,3,3.5] if not bridge else [0,1,2,3]
                    for j,off in enumerate(offsets):
                        self.note('strings',chord[[0,2,1,2][j%4]]+12,at+off,.29,.12*intensity,-.42)
                        self.note('strings',chord[(j+1)%3]+12,at+off,.28,.065*intensity,.44)
                    if section>=2 and not bridge:
                        for j in range(8): self.note('pluck',chord[j%4]+24,at+j*.5+.25,.18,.055*intensity,.37,True)
                kicks=[0,1.5,2,3.5] if spec['mood']=='boss' else [0,1.5,2,2.75]
                if bridge: kicks=[0,2.5]
                for off in kicks: self.drum('kick',at+off,.36*intensity)
                for off in ([2] if bridge else [1,3]): self.drum('snare',at+off,.23*intensity,.06)
                for j in range(8): self.drum('hat',at+j*.5,.085*intensity*(1 if j%2 else .7),.25)
                if not bridge: self.drum('open',at+3.5,.10*intensity,.3)
                if bar%8==0: self.drum('crash',at,.16*intensity,-.35)
                if bar%8==7:
                    for j in range(4): self.drum('tom' if j%2==0 else 'snare',at+3+j*.25,.18*intensity,(-.3+j*.2))
            melody=spec['melody_a' if form=='A' else 'melody_b'][bar%8]
            lead='flute' if bridge and spec['mood']!='chip' else spec['lead']
            transpose=-12 if bridge and spec['mood']=='chip' else 0
            for off,dur,n in phrase(melody):
                # Phrases breathe between notes; final sustained notes release through the next bar.
                gain=(.245 if calm else .235)*(.92 if section==0 else 1)
                self.note(lead,n+transpose,at+off,dur*.91,gain,-.06 if calm else -.02,True)
                if calm and section in (1,3) and off>=2 and bar%2==0:
                    self.note('bell',n,at+off+.015,min(dur,.8),.055,.43,True)
                if not calm and section==5 and n>=72 and not bridge:
                    self.note('strings',n-12,at+off,dur*.88,.085,.32,True)
            # A distinct reply in the last beat, rather than a nonstop lead.
            if calm and bar%4==3:
                for j,n in enumerate(chord[1:]): self.note('bell',n+24,at+3+j*.25,.35,.064,-.3+j*.25,True)
        return self

    def mix(self):
        mix=self.music + self.drums + self.air
        # Circular stereo early reflections plus quiet diffuse taps preserve exact-loop ambience.
        for sec,gain in [(.073,.11),(.113,.085),(.173,.075),(.239,.065),(.347,.052),(.469,.041),(.631,.03),(.829,.021)]:
            tap=np.roll(self.air,round(sec*SR),axis=0)
            mix += tap[:,::-1]*gain
        for beats,gain in [(0.75,.10),(1.5,.045)]:
            mix += np.roll(self.air[:,::-1],round(beats*self.spb*SR),axis=0)*gain
        for sec,gain in [(.051,.055),(.137,.025)]:
            mix += np.roll(self.drums[:,::-1],round(sec*SR),axis=0)*gain
        mix -= np.mean(mix,axis=0)
        mix = np.tanh(mix*.95).astype(np.float32)
        peak=float(np.max(np.abs(mix)))
        mix *= (10**(-3/20))/max(peak,1e-8)
        return mix


def vlq(n):
    out=[n&127]
    while n>>7:
        n>>=7
        out.insert(0,(n&127)|128)
    return bytes(out)


def midi_file(song, path):
    events=[]
    tempo=round(60_000_000/song.spec['bpm'])
    name=song.spec['title'].encode('utf-8')
    events.append((0,b'\xff\x03'+vlq(len(name))+name))
    events.append((0,b'\xff\x51\x03'+tempo.to_bytes(3,'big')))
    events.append((0,b'\xff\x58\x04\x04\x02\x18\x08'))
    for voice,ch in CHANNELS.items(): events.append((0,bytes([0xc0|ch,PROGRAMS[voice]])))
    for voice,note,beat,duration,velocity in song.events:
        ch=9 if voice=='drums' else CHANNELS[voice]
        events.append((round(beat*480),bytes([0x90|ch,note,velocity])))
        events.append((round((beat+duration)*480),bytes([0x80|ch,note,0])))
    events.sort(key=lambda e:(e[0],0 if e[1][0]&0xf0==0x80 else 1))
    data=bytearray();last=0
    for tick,message in events:
        data+=vlq(tick-last)+message;last=tick
    end=song.spec['bars']*4*480
    data+=vlq(max(0,end-last))+b'\xff\x2f\x00'
    path.write_bytes(b'MThd'+struct.pack('>IHHH',6,0,1,480)+b'MTrk'+struct.pack('>I',len(data))+data)


def run_ffmpeg(args):
    result=subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(),'-hide_banner','-nostdin',*args],capture_output=True,text=True,encoding='utf-8',errors='replace')
    if result.returncode: raise RuntimeError(result.stderr[-3000:])
    return result.stderr


def loudness(path):
    log=run_ffmpeg(['-i',str(path),'-af','loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json','-f','null','-'])
    return json.loads(log[log.rfind('{'):log.rfind('}')+1])


def write_wav(path, audio):
    with wave.open(str(path),'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(SR)
        f.writeframes((np.clip(audio,-1,1)*32767).astype('<i2').tobytes())


def render(spec):
    print('Composing:',spec['id'],flush=True)
    song=Song(spec).arrange()
    mix=song.mix()
    raw=PREVIEW/(spec['id']+'_render.wav')
    write_wav(raw,mix)
    measurement=loudness(raw)
    gain=min(spec['lufs']-float(measurement['input_i']), -1.7-float(measurement['input_tp']))
    mix *= 10**(gain/20)
    master=PREVIEW/(spec['id']+'.wav')
    write_wav(master,mix)
    raw.unlink()
    ogg=GAME/(spec['id']+'.ogg')
    metadata=['-metadata',f'title={spec["title"]}','-metadata','artist=RainyArrow original synthesized sketches']
    run_ffmpeg(['-y','-i',str(master),'-c:a','libvorbis','-q:a','6',*metadata,
                '-metadata','LOOPSTART=0','-metadata',f'LOOPEND={song.frames}',str(ogg)])
    run_ffmpeg(['-y','-i',str(master),'-c:a','libmp3lame','-b:a','192k',*metadata,str(PREVIEW/(spec['id']+'.mp3'))])
    midi_file(song,GAME/(spec['id']+'.mid'))
    measured=loudness(ogg)
    # Validate compressed playback length and finite decoded samples, not just renderer arrays.
    decoded=PREVIEW/(spec['id']+'_check.wav')
    run_ffmpeg(['-y','-i',str(ogg),'-c:a','pcm_s16le',str(decoded)])
    with wave.open(str(decoded),'rb') as f:
        frames=f.getnframes();channels=f.getnchannels();rate=f.getframerate()
        samples=np.frombuffer(f.readframes(frames),dtype='<i2').reshape(-1,channels).astype(np.float32)/32768
    decoded.unlink()
    if abs(frames-song.frames)>2 or channels!=2 or rate!=SR: raise RuntimeError('Decoded loop format mismatch')
    if float(np.max(np.abs(samples)))>=.99: raise RuntimeError('Decoded peak is too close to clipping')
    seam=float(np.max(np.abs(samples[0]-samples[-1])))
    delta99=float(np.percentile(np.abs(np.diff(samples,axis=0)),99.9))
    if seam>.025 and seam>delta99*2: raise RuntimeError('Loop boundary spike')
    result={k:spec[k] for k in ['id','title','role','bpm','bars','key','style']}
    result.update(duration_seconds=round(song.frames/SR,3),sample_rate=SR,channels=2,loop_start=0,loop_end=song.frames,
                  integrated_lufs=float(measured['input_i']),true_peak_dbtp=float(measured['input_tp']),
                  loop_boundary_delta=round(seam,6),sample_delta_p999=round(delta99,6),notes=len(song.events),
                  file=ogg.name,midi=spec['id']+'.mid',loop=True)
    print(json.dumps(result,ensure_ascii=False),flush=True)
    return result


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--track',type=int,choices=range(1,6));args=parser.parse_args()
    GAME.mkdir(parents=True,exist_ok=True);PREVIEW.mkdir(parents=True,exist_ok=True)
    results=[]
    for i,spec in enumerate(TRACKS,1):
        if args.track and args.track!=i: continue
        results.append(render(spec))
    if args.track:
        (PREVIEW/f'validation-{args.track}.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    else:
        (GAME/'catalog.json').write_text(json.dumps({'revision':1,'tracks':results},ensure_ascii=False,indent=2),encoding='utf-8')
        (PREVIEW/'validation.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')

if __name__=='__main__': main()
