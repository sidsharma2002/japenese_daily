# Fallback word timing when the Whisper model cannot be downloaded. usage: align.py N  (uses $JP_WORK). Estimated timings only.
import re,json,subprocess
import os,sys
N=sys.argv[1]
D=os.path.abspath(os.environ.get('JP_WORK','jp-work'))+f'/reels/day{N}'
paras=[l for l in open(D+'/script.txt').read().split('\n\n')[1:]]
paras=[re.sub(r'^<\w+>\s*','',p).strip() for p in paras]
out=subprocess.run(['ffmpeg','-i',D+'/narration.wav','-af','silencedetect=noise=-35dB:d=0.25','-f','null','-'],capture_output=True,text=True).stderr
s=[float(x) for x in re.findall(r'silence_start: ([\d.]+)',out)]
e=[float(x) for x in re.findall(r'silence_end: ([\d.]+)',out)]
sil=list(zip(s,e))
T0,T1=0.3,49.42
toks=[];sent_end=set()
for pi,p in enumerate(paras):
    for w in p.split():
        toks.append((pi,w))
def wt(w): return 2+len(re.sub(r'[^\w]','',w))*(1.6 if re.search(r'[぀-ヿ]',w) else 1)
# pause weights after punctuation
W=[wt(w)+(4 if w[-1] in '.?' else 2 if w[-1]==',' else 0)+(4 if i+1<len(toks) and toks[i+1][0]!=toks[i][0] else 0) for i,(pi,w) in enumerate(toks)]
tot=sum(W);t=T0;res=[];ts=[]
for (pi,w),x in zip(toks,W):
    d=x/tot*(T1-T0);ts.append((t,t+d*0.8));t+=d
# snap paragraph starts to silence ends
idx=[next(i for i,(pj,_) in enumerate(toks) if pj==k) for k in range(len(paras))]
shift=[]
for k in idx[1:]:
    est=ts[k][0]
    c=min(sil[1:-1],key=lambda z:abs(z[1]-est)); shift.append((k,c[1]))
# piecewise: rescale each paragraph between snapped starts
starts=[T0]+[b for _,b in shift]+[T1]
bounds=[0]+idx[1:]+[len(toks)]
res=[]
for j in range(len(paras)):
    a,b=bounds[j],bounds[j+1]
    lo,hi=ts[a][0],(ts[b][0] if b<len(toks) else T1)
    ns,ne=starts[j],starts[j+1]-0.25 if j<len(paras)-1 else T1
    for i in range(a,b):
        f=lambda v:ns+(v-lo)/(hi-lo)*(ne-ns)
        res.append({'text':re.sub(r'[.,?]','',toks[i][1]),'start':round(f(ts[i][0]),2),'end':round(f(ts[i][1]),2)})
json.dump(res,open(D+'/transcript.json','w'),indent=0)
print(len(res),[ (r['text'],r['start']) for r in res[::12]])
