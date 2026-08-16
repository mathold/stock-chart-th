"""
เว็บกราฟหุ้นไทย (Streamlit)
============================
พิมพ์ชื่อหุ้นตัวไหนก็ได้ แล้วดึงข้อมูลสดมาวาดกราฟ 4 ไทม์เฟรมทันที

รันในเครื่อง
    pip install -r requirements.txt
    streamlit run app.py

ขึ้นเว็บให้เปิดจาก iPad
    1. เอาไฟล์ทั้งหมดขึ้น GitHub (app.py, thai_stock_dashboard.py,
       requirements.txt, symbols.csv)
    2. เข้า share.streamlit.io → New app → เลือก repo → Main file: app.py
    3. ได้ URL มา เปิดใน Safari บน iPad → Share → Add to Home Screen

ใช้ฟังก์ชันวาดกราฟชุดเดียวกับ thai_stock_dashboard.py ทั้งหมด
แก้สี/อินดิเคเตอร์ที่ไฟล์นั้นไฟล์เดียว ทั้งเว็บและไฟล์ HTML เปลี่ยนตาม
"""

from __future__ import annotations

import csv
import os
from datetime import datetime

import pandas as pd
import streamlit as st

import thai_stock_dashboard as d

HERE = os.path.dirname(os.path.abspath(__file__))
SYMBOLS_CSV = os.path.join(HERE, "symbols.csv")
CACHE_SECONDS = 900                     # จำข้อมูลไว้ 15 นาที กดดูซ้ำจะเร็ว
PLACEHOLDER = "— เลือกจาก SET100 —"

# ดัชนี: ชื่อสัญลักษณ์บน Yahoo ไม่แน่นอน ลองไล่ทีละตัวจนกว่าจะเจอข้อมูล
INDEX_TARGETS = {
    "SET": ["^SET.BK", "^SET", "^SETI"],
    "SET50": ["^SET50.BK", "^SET50", "TDEX.BK"],
}

st.set_page_config(page_title="กราฟหุ้นไทย", page_icon="📈",
                   layout="wide", initial_sidebar_state="collapsed")

# ความสูงกราฟ (px) — ตั้งให้ครบ 4 ช่องพอดีจอเดียวบน iPad Air 11" แนวนอน
# จอ 2360x1640 px @2x = viewport 1180x820 pt · หักแถวควบคุมบน + คำอธิบายล่าง ~70 px
# (Plotly ต้องได้ตัวเลขชัด ๆ ถ้าปล่อย autosize มันจะตกกลับไปใช้ default 450 px)
CHART_HEIGHT_PX = 750

st.markdown(f"""
<style>
  header[data-testid="stHeader"], [data-testid="stToolbar"], footer {{ display: none !important; }}
  .block-container {{ padding: .35rem .6rem .1rem !important; max-width: 100% !important; }}
  [data-testid="stVerticalBlock"] {{ gap: .3rem !important; }}
  [data-testid="stCaptionContainer"] p {{ font-size: .68rem; line-height: 1.2; margin: 0; }}
  [data-testid="stPlotlyChart"], [data-testid="stPlotlyChart"] > div {{
      height: {CHART_HEIGHT_PX}px !important;
  }}
</style>
""", unsafe_allow_html=True)


def _full(fn) -> dict:
    """Streamlit เปลี่ยนจาก use_container_width เป็น width='stretch' — รองรับทั้งสองรุ่น"""
    import inspect
    try:
        params = inspect.signature(fn).parameters
    except (TypeError, ValueError):
        return {"use_container_width": True}
    return {"width": "stretch"} if "width" in params else {"use_container_width": True}


FULL_CHART = _full(st.plotly_chart)
FULL_BTN = _full(st.button)


# ─────────────────────────────────────────────────────────────
# ข้อมูล (มี cache กันดึงซ้ำ)
# ─────────────────────────────────────────────────────────────

@st.cache_data(ttl=CACHE_SECONDS, show_spinner=False)
def _cached_daily(ticker: str) -> pd.DataFrame:
    return d.fetch_daily(ticker)


@st.cache_data(ttl=CACHE_SECONDS, show_spinner=False)
def _cached_intraday(ticker: str) -> pd.DataFrame:
    return d.fetch_intraday(ticker)


def _guard(fn, ticker: str) -> pd.DataFrame:
    """ดึงข้อมูลแบบไม่ให้ error ทำเว็บพัง

    ปล่อยให้ exception หลุดออกมาจากฟังก์ชันที่มี cache ก่อน — Streamlit จะ
    ไม่เก็บผลของรอบที่ error ไว้ ดังนั้นถ้า Yahoo ล่ม/ติด rate limit ชั่วคราว
    กดใหม่แล้วดึงซ้ำได้เลย (เดิมดักเป็น DataFrame ว่างแล้วโดน cache ค้าง 15 นาที)
    """
    try:
        return fn(ticker)
    except Exception as e:                              # noqa: BLE001
        st.session_state.setdefault("fetch_errors", []).append(
            f"{ticker}: {type(e).__name__} — {e}")
        return pd.DataFrame()


def load_daily(ticker: str) -> pd.DataFrame:
    return _guard(_cached_daily, ticker)


def load_intraday(ticker: str) -> pd.DataFrame:
    return _guard(_cached_intraday, ticker)


@st.cache_data(ttl=86400)
def set100() -> list[str]:
    if not os.path.exists(SYMBOLS_CSV):
        return []
    with open(SYMBOLS_CSV, encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        return []
    key = "symbol" if "symbol" in rows[0] else list(rows[0])[0]
    return sorted({(r.get(key) or "").strip().upper() for r in rows} - {""})


def candidates_for(symbol: str) -> list[str]:
    return INDEX_TARGETS.get(symbol.upper(), [f"{symbol.upper()}.BK"])


def build(symbol: str):
    """คืน (figure, สัญลักษณ์ที่ใช้ได้, มี intraday ไหม) หรือ None ถ้าไม่มีข้อมูล"""
    for cand in candidates_for(symbol):
        daily = load_daily(cand)
        if not daily.empty and len(daily) >= 5:
            break
    else:
        return None

    intraday = load_intraday(cand)
    panels = {
        "120m": intraday,
        "Day": daily,
        "Week": d.to_period(daily, "W-FRI"),
        "Month": d.to_period(daily, "ME"),
    }
    return (d.build_figure(symbol.upper(), panels, height=CHART_HEIGHT_PX),
            cand, not intraday.empty)


# ─────────────────────────────────────────────────────────────
# หน้าเว็บ
# ─────────────────────────────────────────────────────────────

st.session_state.setdefault("symbol", "SET")

c1, c2, c3, c4, c5 = st.columns([4, 4, 1.1, 1.3, 1.1])

typed = c1.text_input("ชื่อหุ้น", key="typed", label_visibility="collapsed",
                      placeholder="พิมพ์ชื่อหุ้น เช่น PTT แล้วกด Enter")
names = set100()
choice = c2.selectbox("SET100", [PLACEHOLDER] + names, key="choice",
                      label_visibility="collapsed",
                      disabled=not names)

# ตัวไหนถูกแก้ล่าสุด ตัวนั้นชนะ
if typed != st.session_state.get("_prev_typed"):
    st.session_state._prev_typed = typed
    if typed.strip():
        st.session_state.symbol = typed.strip().upper()

if choice != st.session_state.get("_prev_choice"):
    st.session_state._prev_choice = choice
    if choice != PLACEHOLDER:
        st.session_state.symbol = choice

if c3.button("SET", **FULL_BTN):
    st.session_state.symbol = "SET"
if c4.button("SET50", **FULL_BTN):
    st.session_state.symbol = "SET50"
if c5.button("รีเฟรช", **FULL_BTN, help="ดึงราคาใหม่ ไม่ใช้ข้อมูลที่จำไว้"):
    st.cache_data.clear()

symbol = st.session_state.symbol

st.session_state.fetch_errors = []
with st.spinner(f"กำลังดึงข้อมูล {symbol} ..."):
    result = build(symbol)

if result is None:
    st.error(f"ไม่พบข้อมูลของ **{symbol}**")
    if st.session_state.fetch_errors:
        st.warning("ดึงข้อมูลไม่สำเร็จ (คนละเรื่องกับ 'ไม่มีหุ้นตัวนี้') — "
                   "อาจเน็ตหลุดหรือติด rate limit ของ Yahoo กด **รีเฟรช** ลองใหม่อีกครั้ง")
        st.caption(" · ".join(st.session_state.fetch_errors))
    st.caption("ตรวจตัวสะกดอีกที หุ้นไทยใส่แค่ชื่อย่อ เช่น PTT ไม่ต้องเติม .BK · "
               "หุ้นที่เพิ่งเข้าตลาดหรือสภาพคล่องต่ำ Yahoo อาจยังไม่มีข้อมูล")
    st.stop()

fig, used, has_intraday = result

st.plotly_chart(fig, **FULL_CHART, config={
    "scrollZoom": True, "displaylogo": False, "responsive": True,
})

# รวมเป็นบรรทัดเดียว — ทุก px ที่ประหยัดได้ตรงนี้คือความสูงที่กราฟได้เพิ่ม
note = f"สัญลักษณ์: `{used}` · ณ {datetime.now():%d/%m/%Y %H:%M}"
if not has_intraday:
    note += " · ไม่มี intraday ช่อง 120 นาทีจึงว่าง"
note += (" · ราคาจาก Yahoo Finance เป็นข้อมูลปิดตลาด/ดีเลย์ ไม่ใช่เรียลไทม์ "
         "ใช้ประกอบการศึกษา ตรวจกับโบรกเกอร์ก่อนซื้อขาย")
st.caption(note)
