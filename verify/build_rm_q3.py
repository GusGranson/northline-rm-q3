"""Q3 2026 R&M by branch and month (USD). Standalone: python -I build_rm_q3.py [data_dir]
Applies README rules 1-8 and decisions D-01..D-12. Money is Decimal throughout."""
import csv, re, sys, collections
from decimal import Decimal, ROUND_HALF_UP
from datetime import datetime, date
from pathlib import Path
import openpyxl

D = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent)
CENT = Decimal("0.01")
Q3 = (date(2026, 7, 1), date(2026, 9, 30))
CUTOFF = "2026-09-30 18:00"
WHSE = {**{k: "RIV" for k in ["RIV", "riv", "RIV ", "Riverton "]},
        **{k: "OAK" for k in ["OAK", "oak", " OAK", "Oakdale"]},
        **{k: "PIN" for k in ["PIN", "pin", "PIN ", "Pinecrest"]},
        **{k: "ELM" for k in ["ELM", "Elmwood"]}}
GROUP = {5100, 6100, 6150, 6200, 6300, 6400, 6500}
RM = {6100, 6150, 6200}

def dec(s): return Decimal(str(s).replace(",", "").strip())
def rnd(x): return x.quantize(CENT, ROUND_HALF_UP)
def in_q3(d): return Q3[0] <= d <= Q3[1]

def parse_a(s):
    s = s.strip()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s): return datetime.strptime(s, "%Y-%m-%d").date()
    return datetime.strptime(s, "%m/%d/%Y").date()  # D-03

# ---- ERP-A
with open(D / "erp_a_sro_transactions.csv", encoding="utf-8-sig", newline="") as f:
    rows = list(csv.DictReader(f))
latest = {}
for r in rows:  # D-01: SRO+Line, latest ExportedAt wins
    k = (r["SRO"], r["Line"])
    if k not in latest or r["ExportedAt"] > latest[k]["ExportedAt"]: latest[k] = r
tot = collections.defaultdict(Decimal)
for r in latest.values():
    d = parse_a(r["TransDate"])
    if not in_q3(d):
        continue
    if r["ExportedAt"] > CUTOFF: raise SystemExit(f"D-02 violated: Q3 line first/last seen after cutoff {r['SRO']}-{r['Line']}")
    acct = int(Decimal(r["Acct"].strip()))
    if acct not in GROUP: raise SystemExit(f"unknown account {r['Acct']!r}")
    if acct not in RM: continue
    if int(r["Oper"]) in (75, 100): continue
    if r["Whse"] not in WHSE: raise SystemExit(f"unmapped Whse {r['Whse']!r}")
    b = WHSE[r["Whse"]]
    if b == "ELM" and d >= date(2026, 8, 1): b = "OAK"  # rule 4
    tot[(b, d.strftime("%Y-%m"))] += dec(r["ExtCost"])

# ---- ERP-B
fx = {r["Month"]: dec(r["AvgRate_CADtoUSD"]) for r in csv.DictReader(open(D / "fx_cad_usd.csv", encoding="utf-8-sig"))}
ws = openpyxl.load_workbook(D / "erp_b_lakeshore_gl_detail.xlsx", data_only=True).active
cad = collections.defaultdict(Decimal)
subs = {}
journal = collections.defaultdict(Decimal)
for jid, pdt, acct, desc, amt, src in list(ws.iter_rows(values_only=True))[1:]:
    d = datetime.strptime(pdt, "%d/%m/%Y").date()  # D-03
    a = dec(repr(amt)) if not isinstance(amt, str) else dec(amt)
    a = a.quantize(CENT, ROUND_HALF_UP)  # D-07: removes float noise only
    m = d.strftime("%Y-%m")
    if jid == "SUBTOTAL": subs[(acct, m)] = a; continue
    if not str(jid).startswith("LK"): raise SystemExit(f"bad JournalID {jid}")
    journal[(acct, m)] += a
    if in_q3(d) and re.fullmatch(r"73\d\d-RM(-.*)?", acct):  # rule 6
        cad[m] += a
for k, v in subs.items():  # D-06 control
    if journal[k] != v: raise SystemExit(f"subtotal mismatch {k}: {v} vs {journal[k]}")
for m, v in cad.items(): tot[("LKS", m)] += rnd(v * fx[m])  # rule 5

out = sorted(tot.items(), key=lambda kv: (kv[0][0] , kv[0][1]))
order = {"RIV": 0, "OAK": 1, "PIN": 2, "ELM": 3, "LKS": 4}
out.sort(key=lambda kv: (order[kv[0][0]], kv[0][1]))
with open(D / "rm_q3_by_branch.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(["Branch", "Month", "RM_USD"])
    for (b, m), v in out: w.writerow([b, m, f"{rnd(v):.2f}"])
total = sum(rnd(v) for _, v in out)
for (b, m), v in out: print(b, m, f"{rnd(v):,.2f}")
print("rows", len(out), "TOTAL", f"{total:,.2f}")
