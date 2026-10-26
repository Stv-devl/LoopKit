import json, glob, os, sys
from collections import defaultdict
P={"opus":(4,5,.20,20),"sonnet":(2,2.5,.20,10),"haiku":(.10,.125,.01,.50)}  # cache write 5 min = 1.25x
root=sys.argv[1]; tot=defaultdict(lambda:[0,0.0])
for meta in glob.glob(f"{root}/*/subagents/*.meta.json"):
    try: t=json.load(open(meta)).get("agentType")
    except Exception: continue
    jl=meta.replace(".meta.json",".jsonl"); seen=set(); c=0.0; fam=None
    if not os.path.exists(jl): continue
    for line in open(jl):
        try: e=json.loads(line)
        except Exception: continue
        m=e.get("message") or {}
        if e.get("type")!="assistant" or "usage" not in m or m.get("id") in seen: continue
        seen.add(m.get("id")); mo=m.get("model","")
        fam=next((f for f in P if f in mo),None)
        if not fam: continue
        p=P[fam]; u=m["usage"]
        c+=(u.get("input_tokens",0)*p[0]+u.get("cache_creation_input_tokens",0)*p[1]+u.get("cache_read_input_tokens",0)*p[2]+u.get("output_tokens",0)*p[3])/1e6
    if fam: k=f"{t} ({fam})"; tot[k][0]+=1; tot[k][1]+=c
s=sum(v[1] for v in tot.values())
for k,(n,c) in sorted(tot.items(), key=lambda kv:-kv[1][1]):
    print(f"{k:30} n={n:4}  ${c:8.0f}  {100*c/s:4.0f}%  ${c/n:5.2f}/lancement")
print(f"total ${s:.0f}")
