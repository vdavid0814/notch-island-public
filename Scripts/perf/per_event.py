import json,sys,collections,statistics
d=json.load(open(sys.argv[1]))
rows=d['rows']; ev=d['events']
by=collections.defaultdict(list); byE=collections.defaultdict(list); byPk=collections.defaultdict(list)
for i,(t,u) in enumerate(ev):
    nxt=ev[i+1][0] if i+1<len(ev) else t+3
    win=[r for r in rows if t<=r['t']<min(nxt,t+4)+0.5]
    prevu=ev[i-1][1] if i else ''
    key=u if u!='close' else 'close<'+prevu.split('?')[0]
    by[key].append(sum(r['cpu'] for r in win)/100*1000)  # cpu ms
    byPk[key].append(max([r['cpu'] for r in win] or [0]))
    byE[key].append(max([r['power'] or 0 for r in win] or [0]))
print(f"{'event':28} {'n':>3} {'CPU ms':>7} {'peak %':>7} {'energy pk':>9}")
for k in by:
    print(f"{k:28} {len(by[k]):3} {statistics.mean(by[k]):7.0f} {statistics.mean(byPk[k]):7.1f} {statistics.mean(byE[k]):9.1f}")
