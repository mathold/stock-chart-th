"""
ตัวนับผู้ใช้ — ส่ง log ไปเก็บที่ Google Sheet
==============================================
ใช้ Google Apps Script Web App เป็นตัวรับ (ไม่ต้องมี service account / ไฟล์ JSON)

วิธีตั้งค่า (ทำครั้งเดียว) ดูที่ `ANALYTICS_SETUP.md`
สรุปสั้น ๆ: สร้าง Google Sheet → Extensions > Apps Script → วางโค้ดใน
`analytics_appscript.gs` → Deploy เป็น Web app (Anyone) → ได้ URL มา →
เอาไปใส่ Streamlit Secrets:

    analytics_url = "https://script.google.com/macros/s/.../exec"
    analytics_key = "รหัสลับอะไรก็ได้ ให้ตรงกับใน Apps Script"

**ไม่ตั้ง = ไม่นับ** แอปยังทำงานปกติทุกอย่าง (เหมือน mysig_password)

หลักการที่ต้องรักษาไว้ (อย่ารื้อ):
  • ยิงใน background thread เสมอ — Sheet ช้า/ล่ม ต้องไม่ทำให้กราฟค้าง
  • ห่อ try/except กว้าง ๆ ทุกจุด — ตัวนับพังได้ แต่แอปห้ามพัง
  • Streamlit rerun ทั้งไฟล์ทุกครั้งที่กดปุ่ม จึงต้องกันนับซ้ำด้วย session_state
"""

from __future__ import annotations

import json
import threading
import uuid
from datetime import datetime, timedelta, timezone

import streamlit as st

TIMEOUT = 6                                  # วินาที — ยิงแล้วไม่รอนาน
BKK = timezone(timedelta(hours=7))


def _cfg(name: str) -> str:
    """อ่านค่าจาก secrets แบบไม่ระเบิดตอนไม่มีไฟล์ secrets เลย"""
    try:
        return str(st.secrets.get(name, "")).strip()
    except Exception:                        # noqa: BLE001
        return ""


def enabled() -> bool:
    return bool(_cfg("analytics_url"))


def session_id() -> str:
    """ไอดีสุ่มประจำแท็บ — ใช้แยกว่า 'คนละคน' ไม่ผูกกับตัวตนจริงของใคร"""
    if "an_sid" not in st.session_state:
        st.session_state.an_sid = uuid.uuid4().hex[:12]
    return st.session_state.an_sid


def _post(url: str, payload: dict) -> None:
    """ยิงจริง — รันในเธรดลูก ห้ามโยน exception ออกมา"""
    try:
        import requests
        requests.post(url, json=payload, timeout=TIMEOUT)
    except Exception:                        # noqa: BLE001
        try:                                 # สำรอง เผื่อ requests มีปัญหา
            import urllib.request
            req = urllib.request.Request(
                url, data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"}, method="POST")
            urllib.request.urlopen(req, timeout=TIMEOUT).read()
        except Exception:                    # noqa: BLE001
            pass                             # เก็บไม่ได้ก็ช่างมัน


def log(event: str, detail: str = "") -> None:
    """บันทึก 1 เหตุการณ์ลงชีท — คืนค่าทันที ไม่รอผล"""
    url = _cfg("analytics_url")
    if not url:
        return
    payload = {
        "key": _cfg("analytics_key"),
        "event": event,
        "detail": detail,
        "session": session_id(),
        "time": datetime.now(BKK).strftime("%Y-%m-%d %H:%M:%S"),
    }
    try:
        threading.Thread(target=_post, args=(url, payload), daemon=True).start()
    except Exception:                        # noqa: BLE001
        pass


def log_once(event: str, detail: str = "") -> None:
    """บันทึกครั้งเดียวต่อแท็บ — กันไม่ให้ทุก rerun นับซ้ำ

    Streamlit รันไฟล์ใหม่ทั้งไฟล์ทุกครั้งที่กดปุ่ม/เปลี่ยนหุ้น ถ้าเรียก log()
    ตรง ๆ ที่ระดับบนสุดของ app.py ยอดจะพุ่งเป็นสิบเท่าโดยไม่มีคนเข้าเพิ่ม
    """
    if not enabled():                        # ไม่ได้ตั้งค่า = ไม่ต้องแตะ session_state
        return
    flag = f"an_done_{event}"
    if st.session_state.get(flag):
        return
    st.session_state[flag] = True
    log(event, detail)
