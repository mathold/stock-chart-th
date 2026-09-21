"""
ตัวนับการใช้งาน — ยิงเข้าชีตเดียวกับ SCA App / Ceph Protractor
================================================================
ชีต "สถิติการใช้งาน — SCA App + Ceph Protractor" · ดูผลที่
https://mathold.github.io/sca-app/stats/

ต่างจาก `analytics.py` (ของเดิม ชีตแยกอีกใบ) ตรงที่
  • ยิงจาก "ฝั่งเบราว์เซอร์" ไม่ใช่จากเซิร์ฟเวอร์ — จึงเก็บรหัสเครื่องไว้ใน
    localStorage ได้ รหัสอยู่ถาวรจนกว่าจะล้างข้อมูลเว็บไซต์
    (ของเดิมใช้ uuid ใน session_state = ปิดแท็บ/รีเฟรชแล้วกลายเป็นคนใหม่ทุกครั้ง)
  • นับเฉพาะ "การใช้งานจริง" คือตอนเปลี่ยนหุ้นที่จะดู — เปิดเว็บเฉย ๆ
    หรือกดรีเฟรชไม่นับ (กติกาเดียวกับ SCA = กดคำนวณ · Ceph = กดคัดลอกผลวัด)

หลักการที่ต้องรักษาไว้ (อย่ารื้อ):
  • ห่อ try/except กว้าง ๆ — ตัวนับพังได้ แต่แอปห้ามพัง
  • Streamlit รันไฟล์ใหม่ทั้งไฟล์ทุกครั้งที่กดอะไรสักอย่าง จึง track() เก็บใส่คิว
    แล้วค่อย flush() ทีเดียวท้ายไฟล์ — ตำแหน่ง element จะได้คงที่ทุกรอบ
"""

from __future__ import annotations

import html
import json

import streamlit as st

ENDPOINT = ("https://script.google.com/macros/s/"
            "AKfycbwPgC4WvRnV26rlJhsGqKy_oUbDvSTBtIahNSBKAurciGx1Wl06d4NhqO0rc1P991QSDQ/exec")
APP = "stock"
_QUEUE = "_usage_queue"
_RUN = "_usage_run"


def _embed(markup: str) -> None:
    """ฝัง <script> ลงหน้าเว็บ — st.iframe เป็นตัวใหม่ · components.html กำลังจะถูกถอด
    (Streamlit เตือนเองว่า `st.components.v1.html` จะหายหลัง 1 มิ.ย. 2026)

    height ต้องเป็น 1 ไม่ใช่ 0 — `st.iframe(height=0)` โยน StreamlitInvalidHeightError
    แล้วถูก try/except ข้างนอกกลืนไป กลายเป็นไม่ยิงอะไรเลยแบบเงียบ ๆ
    """
    if hasattr(st, "iframe"):
        try:
            st.iframe(markup, height=1)
            return
        except Exception:                    # noqa: BLE001  เวอร์ชันไหนไม่รับก็ถอยไปตัวเดิม
            pass
    import streamlit.components.v1 as components
    components.html(markup, height=1)


def track(event: str = "open", detail: str = "") -> None:
    """เข้าคิวไว้ 1 เหตุการณ์ — ยังไม่ยิง รอ flush() ท้ายไฟล์"""
    try:
        st.session_state.setdefault(_QUEUE, []).append(
            {"event": str(event)[:20], "detail": str(detail)[:60]})
    except Exception:                        # noqa: BLE001
        pass


def flush() -> None:
    """ยิงทุกเหตุการณ์ในคิวออกไป — เรียกครั้งเดียวที่บรรทัดสุดท้ายของ app.py"""
    try:
        events = st.session_state.pop(_QUEUE, [])
        if not events:
            _embed(_EMPTY)                      # คงตำแหน่ง element ไว้เฉย ๆ
            return
        st.session_state[_RUN] = st.session_state.get(_RUN, 0) + 1
        _embed(_SENDER
               .replace("__ENDPOINT__", html.escape(ENDPOINT, quote=True))
               .replace("__APP__", APP)
               .replace("__EVENTS__", json.dumps(events, ensure_ascii=False))
               .replace("__RUN__", str(st.session_state[_RUN])))
    except Exception:                        # noqa: BLE001
        pass


_EMPTY = "<!-- usage: ไม่มีอะไรต้องนับรอบนี้ -->"

# รหัสเครื่องอยู่ใน localStorage ของหน้าเว็บ (ไม่ใช่ของ iframe) จึงลองฝั่ง parent ก่อน
# — Streamlit ใส่ sandbox allow-same-origin ให้ iframe ของ components.html อยู่แล้ว
# ถ้าเบราว์เซอร์บล็อกจริง ๆ ค่อยตกลงมาใช้ของ iframe เอง แล้วจึง sessionStorage
_SENDER = """
<script>
(function () {
  var ENDPOINT = '__ENDPOINT__', APP = '__APP__', RUN = '__RUN__';
  var EVENTS = __EVENTS__;
  function stores() {
    var out = [];
    try { if (window.parent && window.parent !== window) out.push(window.parent.localStorage); } catch (e) {}
    try { out.push(window.localStorage); } catch (e) {}
    try { out.push(window.sessionStorage); } catch (e) {}
    return out;
  }
  function deviceId() {
    var list = stores(), i, v;
    for (i = 0; i < list.length; i++) {
      try { v = list[i].getItem('stock.device'); } catch (e) { v = null; }
      if (v) { save(list, v); return v; }
    }
    v = (window.crypto && crypto.randomUUID ? crypto.randomUUID()
         : String(Math.random()) + String(Date.now())).replace(/[^a-z0-9]/gi, '').slice(0, 12);
    save(list, v);
    return v;
  }
  function save(list, v) {
    for (var i = 0; i < list.length; i++) { try { list[i].setItem('stock.device', v); } catch (e) {} }
  }
  function p2(n) { return (n < 10 ? '0' : '') + n; }
  function stamp() {
    var d = new Date();
    return d.getFullYear() + '-' + p2(d.getMonth() + 1) + '-' + p2(d.getDate()) + ' ' +
           p2(d.getHours()) + ':' + p2(d.getMinutes()) + ':' + p2(d.getSeconds());
  }
  try {
    var sid = deviceId();
    EVENTS.forEach(function (ev) {
      var body = new URLSearchParams({
        app: APP, event: ev.event || 'open', detail: ev.detail || '', session: sid, t: stamp()
      }).toString();
      if (navigator.sendBeacon) {
        navigator.sendBeacon(ENDPOINT, new Blob([body],
          { type: 'application/x-www-form-urlencoded;charset=UTF-8' }));
      } else {
        fetch(ENDPOINT, { method: 'POST', mode: 'no-cors',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
          body: body });
      }
    });
  } catch (e) {}
})();
</script>
"""
