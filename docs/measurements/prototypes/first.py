import json, glob, os, sys, statistics as st
from collections import defaultdict
root=sys.argv[1]; r=defaultdict(list)
for meta in glob.glob(f"{root}/*/subagents/*.meta.json"):
    try: t=json.load(open(meta)).get("agentType")
    except Exception: continue
    jl=meta.replace(".meta.json",".jsonl")
    if not os.path.exists(jl): continue
    for line in open(jl):
        try: e=json.loads(line)
        except Exception: continue
        m=e.get("message") or {}
        if e.get("type")=="assistant" and "usage" in m:
            u=m["usage"]; r[t].append((u.get("cache_creation_input_tokens",0),u.get("cache_read_input_tokens",0))); break
for t,v in sorted(r.items(), key=lambda kv:-len(kv[1])):
    if len(v)<5: continue
    print(f"{t:18} n={len(v):4} turn1 cw med={st.median(x[0] for x in v):7.0f}  cr med={st.median(x[1] for x in v):7.0f}  hit%={100*sum(1 for x in v if x[1]>x[0])/len(v):.0f}")
