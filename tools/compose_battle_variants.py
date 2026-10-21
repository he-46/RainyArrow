"""Re-orchestrate the existing battle theme using sample-based instruments.

Requires numpy, imageio-ffmpeg, local FluidSynth 2.6.1 and GeneralUser GS 2.0.3.
Original menu/camp tracks and all first-round audio remain untouched.
"""
from pathlib import Path
import hashlib, json, math, struct, subprocess, sys, wave
import numpy as np
import compose_bgm as base

ROOT=base.ROOT
OUT=base.GAME/'battle_v2'
PRE=base.PREVIEW/'battle_v2'
WORK=ROOT/'.tools/music-v2'
SOUNDFONT=ROOT/'.tools/soundfonts/GeneralUser-GS.sf2'
ENGINE=ROOT/'.tools/fluidsynth/fluidsynth-v2.6.1-win10-x64-cpp11/bin/fluidsynth.exe'
BPM=148
BARS=48
TEMPO=round(60000000/BPM)
SPB=TEMPO/1000000
FRAMES=round(BARS*4*SPB*base.SR)
SPECS=[
    dict(id='A_woodland_marimba',title='万箭破晓 · 林野木琴',style='马林巴木琴、尼龙吉他、拨奏弦乐、康加鼓；轻巧有弹性',
         programs={0:12,1:24,2:45,3:43,4:48,9:0},volumes={0:110,1:62,2:56,3:88,4:40,9:80},pans={0:60,1:35,2:87,3:64,4:68,9:64},transpose=0),
    dict(id='B_piano_strings',title='万箭破晓 · 疾行钢琴',style='钢琴、拨奏及长弦乐、大提琴、定音鼓；旋律清楚、有推动感',
         programs={0:0,1:45,2:48,3:32,4:42,6:47,9:0},volumes={0:108,1:58,2:48,3:76,4:57,6:60,9:58},pans={0:59,1:35,2:86,3:64,4:75,6:54,9:64},transpose=-12),
    dict(id='C_horn_wardrums',title='万箭破晓 · 远征号角',style='圆号、弦乐、大提琴、定音鼓与低战鼓；厚实、有出征感',
         programs={0:60,1:48,2:42,3:43,4:48,6:47,9:0},volumes={0:96,1:62,2:58,3:85,4:42,6:74,9:67},pans={0:58,1:35,2:84,3:64,4:85,6:54,9:64},transpose=-12),
]

class Score:
    def __init__(self,spec):
        self.spec=spec;self.notes=[]
        self.rng=np.random.default_rng(7001+ord(spec['id'][0]))
    def note(self,ch,n,start,length,vel):
        # Small deterministic performance changes, locked to the same loop each time.
        velocity=max(1,min(115,round(vel+self.rng.uniform(-3,3))))
        self.notes.append((ch,n,start,length,velocity))
    def arrange(self):
        style=self.spec['id'][0]
        for bar in range(BARS):
            section=bar//8
            bridge=section==3
            form=base.TRACKS[1]['sections'][section]
            chord=base.pitches(base.TRACKS[1]['chords_a' if form=='A' else 'chords_b'][bar%8])
            at=bar*4
            level=[.88,.96,1,.77,.96,1.03][section]
            melody=base.BATTLE_A if form=='A' else base.BATTLE_B
            for off,duration,n in base.phrase(melody[bar%8]):
                articulation=.87 if style=='A' else (.90 if style=='B' else .84)
                self.note(0,n+self.spec['transpose'],at+off,duration*articulation,(85 if style=='A' else 90)*level)
                if style=='B' and section==5 and off in (0,2) and duration>=.5:
                    self.note(0,n,at+off,duration*.82,53)
            root=chord[0]
            bass=root-12 if root>=45 else root
            for off in ([0,2] if bridge else [0,1.5,2,3.5]):
                self.note(3,bass,at+off,.72,82*level)
            # Fewer simultaneous attacks than the original oscillator arrangement.
            if style=='A':
                for j,off in enumerate([0,.75,1.5,2.5,3.25]):
                    self.note(1,chord[[0,2,1,3,2][j]]+12,at+off,.5,71*level)
                for off in (1,3):
                    for n in chord[:3]:self.note(2,n+12,at+off,.28,63*level)
                for n in chord[1:]:self.note(4,n+12,at,3.7,50*level)
                for off in (0,2):self.note(9,36,at+off,.15,66*level)
                for off,n in [(0,64),(.75,62),(1.5,63),(2,64),(2.75,62),(3.5,63)]:
                    self.note(9,n,at+off,.15,(66 if off%1==0 else 55)*level)
                for off in (.5,1.5,2.5,3.5):self.note(9,70,at+off,.12,48*level)
            elif style=='B':
                for j,off in enumerate([0,.5,1.5,2,2.5,3.5] if not bridge else [0,1.5,2.5]):
                    self.note(1,chord[[0,2,1][j%3]]+12,at+off,.32,72*level)
                for n in chord[1:]:self.note(2,n+12,at,3.6,65*level)
                self.note(4,root,at,1.8,74*level)
                self.note(4,chord[2],at+2,1.8,70*level)
                for off in (0,2):self.note(6,38 if bar%2==0 else 45,at+off,.7,72*level)
                for off in (1,3):self.note(9,37,at+off,.1,68*level)
                for off in (.5,2.5):self.note(9,70,at+off,.1,44*level)
            else:
                for j,off in enumerate([0,.5,1.5,2,2.5,3.5] if not bridge else [0,2]):
                    for n in [chord[j%3]+12,chord[(j+1)%3]+12]:self.note(1,n,at+off,.3,67*level)
                self.note(2,root,at,1.75,78*level)
                self.note(2,chord[2],at+2,1.75,73*level)
                for n in chord[1:]:self.note(4,n+12,at,3.65,59*level)
                for off in [0,1.5,2,3.5]:self.note(9,36,at+off,.17,87*level)
                for off in (1,3):self.note(9,41,at+off,.25,70*level)
                for off in (0,2.75):self.note(6,38 if bar%2==0 else 45,at+off,.72,85*level)
            if bar%8==7:
                for j in range(3):
                    self.note(9,([64,63,62] if style=='A' else [45,47,50])[j],at+3.25+j*.25,.16,62*level+j*4)
            if bar%8==0 and style!='A':self.note(9,49,at,.3,45 if bridge else 58)
        return self
    def write_midi(self,path,cycles=1):
        events=[]
        name=self.spec['title'].encode('utf-8')
        events.extend([(0,b'\xff\x03'+base.vlq(len(name))+name),(0,b'\xff\x51\x03'+TEMPO.to_bytes(3,'big')),(0,b'\xff\x58\x04\x04\x02\x18\x08')])
        for ch,program in self.spec['programs'].items():
            events.append((0,bytes([0xc0|ch,program])))
            for cc,v in [(7,self.spec['volumes'][ch]),(10,self.spec['pans'][ch]),(91,0),(93,0)]:events.append((0,bytes([0xb0|ch,cc,v])))
        for cycle in range(cycles):
            for ch,n,start,duration,vel in self.notes:
                tick=round((start+cycle*BARS*4)*480)
                events.extend([(tick,bytes([0x90|ch,n,vel])),(tick+round(duration*480),bytes([0x80|ch,n,0]))])
        events.sort(key=lambda e:(e[0],0 if e[1][0]&0xf0==0x80 else 1))
        data=bytearray();last=0
        for tick,event in events:
            data+=base.vlq(tick-last)+event;last=tick
        data+=base.vlq(max(0,BARS*4*480*cycles-last))+b'\xff\x2f\x00'
        path.write_bytes(b'MThd'+struct.pack('>IHHH',6,0,1,480)+b'MTrk'+struct.pack('>I',len(data))+data)


def main():
    for p in (OUT,PRE,WORK):p.mkdir(parents=True,exist_ok=True)
    accepted=[p for folder in [base.GAME,base.PREVIEW] for p in folder.iterdir() if p.is_file() and p.name.startswith(('01_','03_'))]
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in accepted}
    results=[]
    for spec in SPECS:
        print('Rendering '+spec['id'],flush=True)
        score=Score(spec).arrange()
        score.write_midi(OUT/(spec['id']+'.mid'))
        midi=WORK/(spec['id']+'_three_loops.mid');score.write_midi(midi,3)
        raw=WORK/(spec['id']+'_raw.wav')
        proc=subprocess.run([str(ENGINE),'-ni','-r',str(base.SR),'-g','0.35','-C','0','-R','0','-o','synth.polyphony=256','-o','synth.cpu-cores=1','-O','float','-T','wav','-F',str(raw),str(SOUNDFONT),str(midi)],capture_output=True,text=True,encoding='utf-8',errors='replace')
        if proc.returncode:raise RuntimeError(proc.stdout+proc.stderr)
        (WORK/(spec['id']+'_render.log')).write_text(proc.stdout+proc.stderr,encoding='utf-8')
        pcm=WORK/(spec['id']+'.f32')
        base.run_ffmpeg(['-y','-i',str(raw),'-f','f32le','-c:a','pcm_f32le',str(pcm)])
        full=np.fromfile(pcm,dtype='<f4').reshape(-1,2)
        # Middle pass includes natural note releases from the previous loop.
        mix=full[FRAMES:FRAMES*2].copy()
        if len(mix)!=FRAMES:raise RuntimeError('Unexpected rendered duration')
        # Sample instruments have free-running vibrato and release voices. Bridge the
        # first 45 ms to the next pass's actual continuation, keeping the beat length.
        width=round(.045*base.SR)
        fade=np.sin(np.linspace(0,math.pi/2,width,dtype=np.float32))[:,None]**2
        continuation=full[FRAMES*2:FRAMES*2+width]
        mix[:width]=continuation*(1-fade)+mix[:width]*fade
        mix-=np.mean(mix,axis=0)
        dry=mix.copy()
        for delay,amount in [(.037,.09),(.071,.075),(.113,.055),(.181,.045),(.277,.03),(.409,.02)]:
            mix+=np.roll(dry[:,::-1],round(delay*base.SR),axis=0)*amount
        mix*=10**(-3/20)/max(float(np.max(np.abs(mix))),1e-9)
        temp=WORK/(spec['id']+'_measure.wav');base.write_wav(temp,mix)
        meter=base.loudness(temp)
        gain=min(-17-float(meter['input_i']),-1.5-float(meter['input_tp']))
        mix*=10**(gain/20)
        master=PRE/(spec['id']+'.wav');base.write_wav(master,mix)
        tags=['-metadata',f'title={spec["title"]}','-metadata','artist=RainyArrow / original battle theme, sampled orchestration']
        ogg=OUT/(spec['id']+'.ogg')
        base.run_ffmpeg(['-y','-i',str(master),'-c:a','libvorbis','-q:a','6',*tags,'-metadata','LOOPSTART=0','-metadata',f'LOOPEND={FRAMES}',str(ogg)])
        base.run_ffmpeg(['-y','-i',str(master),'-c:a','libmp3lame','-b:a','192k',*tags,str(PRE/(spec['id']+'.mp3'))])
        # Same 24-second excerpt starts with the first statement in all three versions.
        base.run_ffmpeg(['-y','-i',str(master),'-t','24','-af','afade=t=out:st=23:d=1','-c:a','libmp3lame','-b:a','192k',str(PRE/(spec['id']+'_24s.mp3'))])
        decoded=WORK/(spec['id']+'_decoded.wav')
        base.run_ffmpeg(['-y','-i',str(ogg),'-c:a','pcm_s16le',str(decoded)])
        with wave.open(str(decoded),'rb') as f:
            assert f.getnchannels()==2 and f.getframerate()==base.SR and abs(f.getnframes()-FRAMES)<=2
            samples=np.frombuffer(f.readframes(f.getnframes()),'<i2').reshape(-1,2).astype(np.float32)/32768
        peak=float(np.max(np.abs(samples)));seam=float(np.max(np.abs(samples[0]-samples[-1])))
        delta=float(np.percentile(np.abs(np.diff(samples,axis=0)),99.9))
        assert peak<.99 and not(seam>.025 and seam>delta*2),(peak,seam,delta)
        meter=base.loudness(ogg)
        result={k:spec[k] for k in ['id','title','style']}
        result.update(bpm=BPM,bars=BARS,duration_seconds=FRAMES/base.SR,loop=True,loop_start=0,loop_end=FRAMES,
                      integrated_lufs=float(meter['input_i']),true_peak_dbtp=float(meter['input_tp']),loop_boundary_delta=seam,
                      sample_delta_p999=delta,notes=len(score.notes),programs=spec['programs'],file=ogg.name,
                      source_theme='02_battle_rain_of_arrows',soundfont='GeneralUser GS 2.0.3',renderer='FluidSynth 2.6.1')
        results.append(result)
        print(f'{spec["id"]}: {FRAMES/base.SR:.2f}s, {result["integrated_lufs"]} LUFS, peak {result["true_peak_dbtp"]} dBTP, seam {seam:.5f}',flush=True)
    for path,expected in hashes.items():assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==expected,'Accepted audio changed'
    catalog=dict(revision=2,accepted_original_tracks=['01_menu_moonlit_bow','03_ref_campfire_letters'],
                 preserved_files_sha256=hashes,soundfont_sha256=hashlib.sha256(SOUNDFONT.read_bytes()).hexdigest(),tracks=results)
    (PRE/'validation.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8')
    catalog.pop('preserved_files_sha256')
    (OUT/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'Accepted files unchanged: {len(hashes)}. Three battle arrangements complete.',flush=True)

if __name__=='__main__':main()
