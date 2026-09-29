import sqlite3, datetime as dt, itertools
con=sqlite3.connect(':memory:'); con.row_factory=sqlite3.Row
con.executescript(open('setup.sql').read())
T=lambda s: dt.datetime.fromisoformat(s)
D=lambda s: dt.date.fromisoformat(s) if s else None
q=lambda s: [dict(r) for r in con.execute(s)]
ev={r['evidence_id']:r for r in q("select * from evidence")}
cs={r['case_id']:r for r in q("select * from cases")}
loc={r['location_id']:r for r in q("select * from locations")}
ppl={r['person_id']:r for r in q("select * from people")}
dev={r['device_id']:r for r in q("select * from devices")}
tr=q("select * from evidence_transfers"); 
for r in tr: r['t']=T(r['transfer_time'])
acc=q("select * from access_logs"); [r.__setitem__('t',T(r['access_time'])) for r in acc]
calls=q("select * from calls"); [r.__setitem__('t',T(r['call_time'])) for r in calls]
sig=q("select * from person_location"); [r.__setitem__('t',T(r['observed_at'])) for r in sig]

def solve(V={}):
    g=lambda k,d: V.get(k,d)
    inc=[]
    for x in tr:
        same=[y for y in tr if y['evidence_id']==x['evidence_id']]
        later=[y for y in same if (y['t'],y['transfer_id'])>(x['t'],x['transfer_id'])]
        earlier=[y for y in same if (y['t'],y['transfer_id'])<(x['t'],x['transfer_id'])]
        if g('earlier_tie_by_time_only',False):
            earlier=[y for y in same if y['t']<x['t']]
        if g('earlier_must_change_room',False):
            earlier=[y for y in earlier if y['from_location_id']!=y['to_location_id']]
        e=ev[x['evidence_id']]; c=cs[e['case_id']]
        if later: continue
        if not(e['sealed'] and e['status']=='Missing' and x['seal_state']=='sealed'): continue
        if not(c['case_type']=='Theft' and c['status']=='Closed' and D(c['closed_on'])<x['t'].date()): continue
        if x['from_location_id']!=c['origin_location_id']: continue
        if len(earlier)<2: continue
        if e['current_location_id']==x['to_location_id']: continue
        inc.append(x)
    if len(inc)!=1: return ('incident_count',len(inc))
    I=inc[0]; tau=I['t']; w0=tau-dt.timedelta(hours=3)
    if g('excl_start',False): inwin=lambda t: w0<t<=tau
    else: inwin=lambda t: w0<=t<=tau
    bld=loc[I['to_location_id']]['building']
    shadow={k for k,v in loc.items() if v['building']==bld and v['restricted']}
    if g('excl_dest',False): shadow-={I['to_location_id']}
    # first tier
    tier1=set()
    for p in ppl:
        ent=[a for a in acc if a['person_id']==p and a['location_id'] in shadow and a['action']=='ENTRY' and a['result']=='GRANTED' and a['escort_id'] is None and inwin(a['t'])]
        if not ent: continue
        sus=[a for a in ent if a['anomaly_flag']=='Y' and ppl[p]['clearance_level']<loc[a['location_id']]['badge_level_required']]
        cond1 = (len(sus)*2>=len(ent)) if g('half_ge',False) else (len(sus)*2>len(ent))
        mc=g('minconf',0.70)
        s=[x for x in sig if x['person_id']==p and x['t']<=tau and float(x['confidence'])>=mc]
        if not s: continue
        last=max(s,key=lambda x:(x['t'],x['event_id']))
        if cond1 and last['location_id'] in shadow: tier1.add(p)
    def valid(c):
        d=dev[c['device_id']]
        if c['call_type']!='voice': return False
        if not g('ignore_answered',False) and not c['answered']: return False
        if c['duration_sec']<g('mindur',30): return False
        if not inwin(c['t']): return False
        if not g('ignore_dev',False):
            if d['owner_id']!=c['caller_id']: return False
            if D(d['issued_on'])>c['t'].date(): return False
            if d['retired_on'] and not D(d['retired_on'])>c['t'].date(): return False
        return True
    vc=[c for c in calls if valid(c)]
    tier2=set()
    for p in ppl:
        if p in tier1: continue
        others={(c['receiver_id'] if c['caller_id']==p else c['caller_id']) for c in vc if p in (c['caller_id'],c['receiver_id'])}
        if len(others&tier1)>=3: tier2.add(p)
    ring=tier1|tier2
    S=0; ids=[]
    for c in vc:
        if c['caller_id'] in ring and c['receiver_id'] in ring:
            lo=c['t']-dt.timedelta(minutes=60)
            lohi=(lambda t: lo<=t<=c['t']) if g('coord_incl_left',False) else (lambda t: lo<t<=c['t'])
            a=any(x['person_id']==c['caller_id'] and x['location_id'] in shadow and x['action']=='ENTRY' and x['result']=='GRANTED' and lohi(x['t']) for x in acc)
            b=any(x['person_id']==c['caller_id'] and x['location_id'] in shadow and float(x['confidence'])>=0.70 and lohi(x['t']) for x in sig)
            if a or b: S+=c['duration_sec']; ids.append(c['call_id'])
    W=int(round(float(ev[I['evidence_id']]['weight_grams'])*10))
    return dict(inc=I['transfer_id'],tier1=sorted(tier1),tier2=sorted(tier2),calls=ids,S=S,R=len(ring),W=W,ans=S*len(ring)+W)
print("BASE",solve())
for name in ['excl_start','excl_dest','half_ge','coord_incl_left','ignore_answered','ignore_dev','earlier_must_change_room','earlier_tie_by_time_only']:
    print(name,solve({name:True}))
print('mindur31',solve({'mindur':31}),'mindur1',solve({'mindur':1}),'minconf.71',solve({'minconf':0.71}),'minconf.5',solve({'minconf':0.5}))
