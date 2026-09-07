import json, os, glob, sqlite3, sys, datetime, collections

cutoff = datetime.datetime.fromisoformat(sys.argv[1]).astimezone()
print("cutoff:", cutoff.isoformat())

# ---- Claude Code reference: dedupe on message.id + requestId ----
seen = set()
ain = aout = acw = acr = acalls = 0
for p in glob.glob(os.path.expanduser("~/.claude/projects/**/*.jsonl"), recursive=True):
    for line in open(p, errors="ignore"):
        if '"usage"' not in line: continue
        try: d = json.loads(line)
        except Exception: continue
        m = d.get("message") or {}
        u = m.get("usage") or {}
        if not u: continue
        key = (m.get("id") or "") + "|" + (d.get("requestId") or "")
        if key != "|" and key in seen: continue
        ts = d.get("timestamp")
        if not ts: continue
        dt = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone()
        if dt < cutoff: continue
        if key != "|": seen.add(key)
        ain += u.get("input_tokens", 0) or 0
        aout += u.get("output_tokens", 0) or 0
        acw += u.get("cache_creation_input_tokens", 0) or 0
        acr += u.get("cache_read_input_tokens", 0) or 0
        acalls += 1
print("CLAUDE  input=%d output=%d cacheWrite=%d cacheRead=%d calls=%d" % (ain, aout, acw, acr, acalls))

# ---- Codex reference: bank each rise in the session's cumulative total ----
cin = cout = ccached = ccalls = 0
for p in sorted(glob.glob(os.path.expanduser("~/.codex/sessions/**/*.jsonl"), recursive=True)):
    if datetime.datetime.fromtimestamp(os.path.getmtime(p)).astimezone() < cutoff:
        continue
    prev = [0, 0, 0]
    for line in open(p, errors="ignore"):
        if '"token_count"' not in line: continue
        try: d = json.loads(line)
        except Exception: continue
        pl = d.get("payload") or {}
        if pl.get("type") != "token_count": continue
        info = pl.get("info")
        if not info: continue
        t = info.get("total_token_usage") or {}
        cur = [t.get("input_tokens",0) or 0, t.get("cached_input_tokens",0) or 0, t.get("output_tokens",0) or 0]
        if not all(c >= q for c, q in zip(cur, prev)):
            prev = cur; continue
        delta = [c - q for c, q in zip(cur, prev)]
        prev = cur
        if not any(x > 0 for x in delta): continue
        ts = d.get("timestamp")
        if not ts: continue
        dt = datetime.datetime.fromisoformat(ts.replace("Z","+00:00")).astimezone()
        if dt < cutoff: continue
        ccached += delta[1]
        cin += max(0, delta[0] - delta[1])
        cout += delta[2]
        ccalls += 1
print("CODEX   input=%d output=%d cacheRead=%d calls=%d" % (cin, cout, ccached, ccalls))

# ---- Gemini CLI reference: whole-file sessions, deduped by message id ----
gseen = set()
gin = gout = gcr = gcalls = 0
for p in glob.glob(os.path.expanduser("~/.gemini/tmp/*/chats/session-*.json")):
    if datetime.datetime.fromtimestamp(os.path.getmtime(p)).astimezone() < cutoff:
        continue
    try: doc = json.load(open(p))
    except Exception: continue
    for m in doc.get("messages", []):
        t = m.get("tokens")
        if not t: continue
        mid = m.get("id") or ""
        if mid and mid in gseen: continue
        ts = m.get("timestamp")
        if not ts: continue
        dt = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone()
        if dt < cutoff: continue
        if mid: gseen.add(mid)
        cached = t.get("cached", 0) or 0
        gin += max(0, (t.get("input", 0) or 0) - cached) + (t.get("tool", 0) or 0)
        gout += (t.get("output", 0) or 0) + (t.get("thoughts", 0) or 0)
        gcr += cached
        gcalls += 1
print("GEMINI  input=%d output=%d cacheRead=%d calls=%d" % (gin, gout, gcr, gcalls))

# ---- Cursor reference: composer createdAt, sum its bubbles' tokenCount ----
db = os.path.expanduser("~/Library/Application Support/Cursor/User/globalStorage/state.vscdb")
uin = uout = ucalls = 0
if os.path.exists(db):
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    look = "SELECT value FROM cursorDiskKV WHERE key = ?"
    for (v,) in con.execute("SELECT value FROM cursorDiskKV WHERE key LIKE 'composerData:%'"):
        if not v: continue
        try: o = json.loads(v)
        except Exception: continue
        cid = o.get("composerID") or o.get("composerId")
        ms = o.get("createdAt")
        if not cid or not isinstance(ms,(int,float)): continue
        if datetime.datetime.fromtimestamp(ms/1000).astimezone() < cutoff: continue
        for h in (o.get("fullConversationHeadersOnly") or []):
            bid = h.get("bubbleId") if isinstance(h, dict) else h
            if not bid: continue
            r = con.execute(look, (f"bubbleId:{cid}:{bid}",)).fetchone()
            if not r or not r[0]: continue
            try: b = json.loads(r[0])
            except Exception: continue
            tc = b.get("tokenCount") or {}
            i = tc.get("inputTokens",0) or 0; ou = tc.get("outputTokens",0) or 0
            if not (i or ou): continue
            uin += i; uout += ou; ucalls += 1
print("CURSOR  input=%d output=%d calls=%d" % (uin, uout, ucalls))
