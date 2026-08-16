"""
ดึงรายชื่อหุ้นใน SET100 มาเก็บเป็น symbols.csv
================================================

    python fetch_symbols.py                    # ลองดึงจาก SET อัตโนมัติ
    python fetch_symbols.py รายชื่อ.xlsx        # แปลงจากไฟล์ที่โหลดมาเอง

ลำดับการทำงาน
  1. ลองเรียก API ของ SET หลายรูปแบบ
  2. ถ้าไม่สำเร็จ ใช้รายชื่อสำรองในไฟล์นี้ (FALLBACK_SET100)

⚠ รายชื่อ SET100 ถูกทบทวนทุก 6 เดือน (รอบ ม.ค. และ ก.ค.)
  รายชื่อสำรองด้านล่างมาจากข้อมูลเดิมที่มีอยู่ อาจไม่ตรงกับรอบล่าสุด
  ตรวจกับ set.or.th แล้วแก้ symbols.csv ได้โดยตรง — สคริปต์อื่นอ่านจากไฟล์นั้น
"""

from __future__ import annotations

import csv
import os
import sys

OUTPUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "symbols.csv")

ENDPOINTS = [
    "https://www.set.or.th/api/set/index/set100/composition?language=en",
    "https://www.set.or.th/api/set/index/SET100/composition",
    "https://www.set.or.th/api/set/index/set100/composition",
]

HEADERS = {
    "User-Agent": ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                   "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"),
    "Accept": "application/json",
    "Referer": "https://www.set.or.th/",
}

# รายชื่อสำรอง — แก้ได้ตามรอบทบทวนล่าสุด
FALLBACK_SET100 = """
AAV ADVANC AMATA AOT AWC BA BAM BANPU BBL BCH BCP BCPG BDMS BEM BGRIM BH BJC BLA
BTS CBG CENTEL CHG CK CKP COM7 CPALL CPAXT CPF CPN CRC DELTA DOHOME EA EGCO ERW
GFPT GLOBAL GPSC GULF GUNKUL HANA HMPRO ICHI IRPC ITC IVL JMART JMT KBANK KCE KKP
KTB KTC LH M MEGA MINT MTC OR OSP PLANB PRM PSL PTG PTT PTTEP PTTGC QH RATCH RCL
SAWAD SCB SCC SCCC SCGP SIRI SJWD SNNP SPALI SPRC STA STEC STGT SUPER TASCO TCAP
TIDLOR TIPH TISCO TLI TOA TOP TQM TRUE TTB TTW TU TVO VGI WHA WHAUP
""".split()


def from_set_api() -> list[str]:
    try:
        import requests
    except ImportError:
        print("  ไม่ได้ติดตั้ง requests — ข้ามการดึงอัตโนมัติ")
        return []

    for url in ENDPOINTS:
        try:
            r = requests.get(url, headers=HEADERS, timeout=20)
            r.raise_for_status()
            data = r.json()
        except Exception as e:                              # noqa: BLE001
            print(f"  ไม่สำเร็จ: {url}  ({type(e).__name__})")
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
        if len(syms) >= 50:
            print(f"  สำเร็จ: ได้ {len(syms)} ตัว จาก {url}")
            return syms
    return []


def from_local_file(path: str) -> list[str]:
    import pandas as pd

    df = pd.read_excel(path) if path.lower().endswith((".xlsx", ".xls")) else pd.read_csv(path)
    df.columns = [str(c).strip().lower() for c in df.columns]
    col = next((c for c in df.columns if c in ("symbol", "หลักทรัพย์", "ชื่อย่อ")), df.columns[0])
    return [str(v).strip().upper() for v in df[col] if str(v).strip() and str(v).lower() != "nan"]


def save(symbols: list[str], source: str) -> None:
    symbols = sorted(set(symbols))
    with open(OUTPUT, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["symbol"])
        w.writerows([[s] for s in symbols])
    print(f"\nเซฟแล้ว: {OUTPUT}")
    print(f"  {len(symbols)} ตัว · ที่มา: {source}")


def main():
    if len(sys.argv) > 1:
        print(f"อ่านรายชื่อจาก {sys.argv[1]}")
        save(from_local_file(sys.argv[1]), "ไฟล์ที่ผู้ใช้ให้มา")
        return

    print("ลองดึงรายชื่อ SET100 จาก SET ...")
    syms = from_set_api()
    if syms:
        save(syms, "SET API")
        return

    print("\nดึงอัตโนมัติไม่สำเร็จ — ใช้รายชื่อสำรองแทน")
    print("⚠ อาจไม่ตรงกับรอบทบทวนล่าสุด ตรวจกับ set.or.th แล้วแก้ symbols.csv ได้เลย")
    save(FALLBACK_SET100, "รายชื่อสำรองในสคริปต์ (ต้องตรวจสอบ)")


if __name__ == "__main__":
    main()
