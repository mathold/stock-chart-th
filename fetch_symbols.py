"""
ดึงรายชื่อหุ้นแยกตามกลุ่ม มาเก็บเป็น symbols.csv
=================================================

    python fetch_symbols.py                          # ลองดึงจาก SET อัตโนมัติทุกกลุ่ม
    python fetch_symbols.py รายชื่อ.xlsx --group mai  # แปลงจากไฟล์ที่โหลดมาเอง (กลุ่มเดียว)

กลุ่มที่รองรับ: SET50 · SET100 · mai   (ดู GROUPS ด้านล่าง)

ลำดับการทำงาน
  1. ลองเรียก API ของ SET ทีละกลุ่ม
  2. กลุ่มไหนไม่สำเร็จ ใช้รายชื่อสำรองในไฟล์นี้ (FALLBACK)

ผลลัพธ์ symbols.csv มี 2 คอลัมน์: symbol, group

⚠ รายชื่อสำรองด้านล่าง **ต้องตรวจสอบก่อนใช้จริง**
  SET50/SET100 ทบทวนทุก 6 เดือน (รอบ ม.ค. และ ก.ค.) · mai มีบริษัทเข้า/ออกตลอด
  วิธีอัปเดตที่แม่นที่สุด: โหลดรายชื่อจาก set.or.th มาเป็นไฟล์ Excel/CSV แล้วสั่ง
      python fetch_symbols.py ไฟล์ที่โหลดมา.xlsx --group SET50
  (กลุ่มอื่นใน symbols.csv จะถูกเก็บไว้เหมือนเดิม แก้เฉพาะกลุ่มที่ระบุ)

หมายเหตุ warrant: Yahoo Finance ไม่มีข้อมูลใบสำคัญแสดงสิทธิของไทยเลย
  (ลองแล้วทั้ง TRUE-W5.BK / TRUEW5.BK ฯลฯ ไม่มีสักแบบ) จึงไม่ใส่กลุ่ม warrant
  เพราะเลือกมาก็วาดกราฟไม่ได้
"""

from __future__ import annotations

import csv
import os
import sys

OUTPUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "symbols.csv")

# กลุ่ม -> endpoint ของ SET ที่จะลองไล่ทีละอัน
GROUPS = {
    "SET50": [
        "https://www.set.or.th/api/set/index/set50/composition?language=en",
        "https://www.set.or.th/api/set/index/SET50/composition",
    ],
    "SET100": [
        "https://www.set.or.th/api/set/index/set100/composition?language=en",
        "https://www.set.or.th/api/set/index/SET100/composition",
    ],
    "mai": [
        "https://www.set.or.th/api/set/index/mai/composition?language=en",
        "https://www.set.or.th/api/set/index/MAI/composition",
    ],
}

HEADERS = {
    "User-Agent": ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                   "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"),
    "Accept": "application/json",
    "Referer": "https://www.set.or.th/",
}

# ── รายชื่อสำรอง — แก้ได้ตามรอบทบทวนล่าสุด ──────────────────────────────

FALLBACK = {
    "SET50": """
AOT ADVANC AWC BANPU BBL BCP BDMS BEM BGRIM BH BTS CBG CENTEL CPALL CPAXT CPF CPN
CRC DELTA EA GLOBAL GPSC GULF HMPRO IVL KBANK KCE KTB KTC LH MINT MTC OR OSP PTT
PTTEP PTTGC RATCH SAWAD SCB SCC SCGP TIDLOR TISCO TLI TOP TRUE TTB TU WHA
""".split(),

    "SET100": """
AAV ADVANC AMATA AOT AWC BA BAM BANPU BBL BCH BCP BCPG BDMS BEM BGRIM BH BJC BLA
BTS CBG CENTEL CHG CK CKP COM7 CPALL CPAXT CPF CPN CRC DELTA DOHOME EA EGCO ERW
GFPT GLOBAL GPSC GULF GUNKUL HANA HMPRO ICHI IRPC ITC IVL JMART JMT KBANK KCE KKP
KTB KTC LH M MEGA MINT MTC OR OSP PLANB PRM PSL PTG PTT PTTEP PTTGC QH RATCH RCL
SAWAD SCB SCC SCCC SCGP SIRI SJWD SNNP SPALI SPRC STA STEC STGT SUPER TASCO TCAP
TIDLOR TIPH TISCO TLI TOA TOP TQM TRUE TTB TTW TU TVO VGI WHA WHAUP
""".split(),

    # ตรวจแล้วว่า Yahoo มีข้อมูลราคาครบทุกตัว (16/08/2026)
    # แต่ "อยู่ตลาด mai จริงไหม" ยังต้องตรวจกับ set.or.th อีกที
    "mai": """
APP ARIN AU D DOD EASON ECF ETC GTV ICN INSET JUBILE KUMWEL KWM MOONG MVP NCL
NETBAY PIS PPS PROEN PROS READY RT SAV SIMAT SORKON STC TIGER TM TPS UEC UREKA
XPG YGG ZIGA
""".split(),
}


def from_set_api(urls: list[str]) -> list[str]:
    try:
        import requests
    except ImportError:
        print("  ไม่ได้ติดตั้ง requests — ข้ามการดึงอัตโนมัติ")
        return []

    for url in urls:
        try:
            r = requests.get(url, headers=HEADERS, timeout=20)
            r.raise_for_status()
            data = r.json()
        except Exception as e:                              # noqa: BLE001
            print(f"    ไม่สำเร็จ: {url}  ({type(e).__name__})")
            continue

        items = (data.get("constituents") or data.get("securitySymbols")
                 or data.get("data") or data) if isinstance(data, dict) else data
        if not isinstance(items, list):
            continue

        syms = []
        for it in items:
            sym = it.get("symbol") if isinstance(it, dict) else str(it)
            if sym:
                syms.append(str(sym).strip().upper())
        if len(syms) >= 20:
            print(f"    สำเร็จ: ได้ {len(syms)} ตัว จาก {url}")
            return syms
    return []


def from_local_file(path: str) -> list[str]:
    import pandas as pd

    df = pd.read_excel(path) if path.lower().endswith((".xlsx", ".xls")) else pd.read_csv(path)
    df.columns = [str(c).strip().lower() for c in df.columns]
    col = next((c for c in df.columns if c in ("symbol", "หลักทรัพย์", "ชื่อย่อ")), df.columns[0])
    return [str(v).strip().upper() for v in df[col] if str(v).strip() and str(v).lower() != "nan"]


def read_existing() -> dict[str, list[str]]:
    """อ่าน symbols.csv เดิม เพื่อจะได้แก้ทีละกลุ่มโดยไม่ทับกลุ่มอื่น"""
    if not os.path.exists(OUTPUT):
        return {}
    out: dict[str, list[str]] = {}
    with open(OUTPUT, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            sym = (row.get("symbol") or "").strip().upper()
            if sym:
                out.setdefault((row.get("group") or "SET100").strip(), []).append(sym)
    return out


def save(by_group: dict[str, list[str]], sources: dict[str, str]) -> None:
    order = list(GROUPS) + [g for g in by_group if g not in GROUPS]
    with open(OUTPUT, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["symbol", "group"])
        for g in order:
            for s in sorted(set(by_group.get(g, []))):
                w.writerow([s, g])

    print(f"\nเซฟแล้ว: {OUTPUT}")
    for g in order:
        if by_group.get(g):
            print(f"  {g:7s} {len(set(by_group[g])):3d} ตัว · ที่มา: {sources.get(g, 'ของเดิมในไฟล์')}")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    group_arg = None
    if "--group" in sys.argv:
        i = sys.argv.index("--group")
        if i + 1 < len(sys.argv):
            group_arg = sys.argv[i + 1]

    # โหมดแปลงไฟล์: แก้เฉพาะกลุ่มที่ระบุ กลุ่มอื่นคงเดิม
    if args:
        group = group_arg or "SET100"
        print(f"อ่านรายชื่อจาก {args[0]} → กลุ่ม {group}")
        by_group = read_existing() or {g: list(v) for g, v in FALLBACK.items()}
        by_group[group] = from_local_file(args[0])
        save(by_group, {group: "ไฟล์ที่ผู้ใช้ให้มา"})
        return

    by_group: dict[str, list[str]] = {}
    sources: dict[str, str] = {}
    for group, urls in GROUPS.items():
        print(f"ลองดึงรายชื่อ {group} จาก SET ...")
        syms = from_set_api(urls)
        if syms:
            by_group[group], sources[group] = syms, "SET API"
            continue
        print(f"    ใช้รายชื่อสำรองแทน ({len(FALLBACK[group])} ตัว)")
        by_group[group], sources[group] = list(FALLBACK[group]), "รายชื่อสำรอง (ต้องตรวจสอบ)"

    save(by_group, sources)
    if any("สำรอง" in s for s in sources.values()):
        print("\n⚠ มีกลุ่มที่ใช้รายชื่อสำรอง อาจไม่ตรงรอบทบทวนล่าสุด")
        print("  ตรวจกับ set.or.th แล้วแก้ symbols.csv ตรง ๆ หรือสั่ง")
        print("  python fetch_symbols.py ไฟล์.xlsx --group SET50")


if __name__ == "__main__":
    main()
