import json, glob, os, sys, statistics as st
from collections import defaultdict
root = sys.argv[1]
agg = defaultdict(lambda: {"n":0,"in":0,"cw":0,"cr":0,"out":0,"per":[], "turns":[]})
for meta in glob.glob(f"{root}/*/subagents/*.meta.json"):
    try: m = json.load(open(meta))
    except Exception: continue
    t = m.get("agentType","?")
    jl = meta.replace(".meta.json",".jsonl")
    if not os.path.exists(jl): continue
    seen=set(); model=None; tot={"in":0,"cw":0,"cr":0,"out":0}; turns=0
    for line in open(jl):
        try: e=json.loads(line)
        except Exception: continue
        msg=e.get("message") or {}
        if e.get("type")!="assistant" or "usage" not in msg: continue
        mid=msg.get("id")
        if mid in seen: continue
        seen.add(mid); turns+=1
        model=msg.get("model",model); u=msg["usage"]
        tot["in"]+=u.get("input_tokens",0); tot["cw"]+=u.get("cache_creation_input_tokens",0)
        tot["cr"]+=u.get("cache_read_input_tokens",0); tot["out"]+=u.get("output_tokens",0)
    if not turns: continue
    k=(t,model); a=agg[k]; a["n"]+=1; a["turns"].append(turns)
    for x in tot: a[x]+=tot[x]
    a["per"].append(tot)
print(f"{'agent':18}{'model':22}{'n':>5}{'turns':>6}{'in':>8}{'cw':>9}{'cr':>11}{'out':>8}  out/fresh%")
for (t,mo),a in sorted(agg.items(), key=lambda kv:-kv[1]["n"]):
    n=a["n"]; fresh=a["in"]+a["cw"]
    print(f"{t:18}{str(mo)[:21]:22}{n:5}{st.median(a['turns']):6.0f}{a['in']//n:8}{a['cw']//n:9}{a['cr']//n:11}{a['out']//n:8}  {100*a['out']/max(1,fresh+a['out']):.0f}")
