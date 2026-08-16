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

import pandas as pd
import streamlit as st

import thai_stock_dashboard as d

HERE = os.path.dirname(os.path.abspath(__file__))
SYMBOLS_CSV = os.path.join(HERE, "symbols.csv")
CACHE_SECONDS = 900                     # จำข้อมูลไว้ 15 นาที กดดูซ้ำจะเร็ว
GROUP_ORDER = ["SET50", "SET100", "mai", "US",             # ลำดับในช่องเลือกกลุ่ม
               "Crypto", "Commodity", "Index"]

# ความยาวแท่งของช่อง intraday (นาที) — ไทยวันทำการสั้นกว่า เลยใช้แท่งถี่กว่า
INTRADAY_MINUTES_TH = 120
INTRADAY_MINUTES_GLOBAL = 240           # หุ้นเมกา + คริปโต

# กลุ่มไหนอยู่ตลาดไหน — ใช้ตัดสินว่าจะเติม .BK / -USD ให้ชื่อย่อไหม
# "Raw" = ชื่อในลิสต์เป็นชื่อบน Yahoo อยู่แล้ว (GC=F, ^GSPC) ใช้ตรง ๆ ห้ามเติมอะไร
GROUP_MARKET = {"SET50": "TH", "SET100": "TH", "mai": "TH",
                "US": "US", "Crypto": "Crypto",
                "Commodity": "Raw", "Index": "Raw"}

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
def _cached_intraday(ticker: str, minutes: int) -> pd.DataFrame:
    return d.fetch_intraday(ticker, minutes)


def _guard(fn, ticker: str, *extra) -> pd.DataFrame:
    """ดึงข้อมูลแบบไม่ให้ error ทำเว็บพัง

    ปล่อยให้ exception หลุดออกมาจากฟังก์ชันที่มี cache ก่อน — Streamlit จะ
    ไม่เก็บผลของรอบที่ error ไว้ ดังนั้นถ้า Yahoo ล่ม/ติด rate limit ชั่วคราว
    กดใหม่แล้วดึงซ้ำได้เลย (เดิมดักเป็น DataFrame ว่างแล้วโดน cache ค้าง 15 นาที)
    """
    try:
        return fn(ticker, *extra)
    except Exception as e:                              # noqa: BLE001
        st.session_state.setdefault("fetch_errors", []).append(
            f"{ticker}: {type(e).__name__} — {e}")
        return pd.DataFrame()


def load_daily(ticker: str) -> pd.DataFrame:
    return _guard(_cached_daily, ticker)


def load_intraday(ticker: str, minutes: int) -> pd.DataFrame:
    return _guard(_cached_intraday, ticker, minutes)


@st.cache_data(ttl=86400)
def symbol_groups() -> tuple[dict[str, list[str]], dict[str, str]]:
    """อ่าน symbols.csv → ({กลุ่ม: [ชื่อย่อ]}, {ชื่อย่อ: ชื่อไทย})

    เรียงตามลำดับในไฟล์ (ดัชนี/สินค้าโภคภัณฑ์เรียงตัวสำคัญขึ้นก่อน)
    ไฟล์รุ่นเก่าที่มีแต่คอลัมน์ symbol ก็ยังอ่านได้ (นับเป็นกลุ่ม SET100 ทั้งหมด)
    """
    if not os.path.exists(SYMBOLS_CSV):
        return {}, {}
    with open(SYMBOLS_CSV, encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        return {}, {}

    key = "symbol" if "symbol" in rows[0] else list(rows[0])[0]
    groups: dict[str, list[str]] = {}
    labels: dict[str, str] = {}
    for r in rows:
        sym = (r.get(key) or "").strip().upper()
        if not sym:
            continue
        g = groups.setdefault((r.get("group") or "SET100").strip(), [])
        if sym not in g:
            g.append(sym)
        name = (r.get("name") or "").strip()
        if name:
            labels[sym] = f"{sym} — {name}"

    order = [g for g in GROUP_ORDER if g in groups] + \
            [g for g in groups if g not in GROUP_ORDER]
    return {g: groups[g] for g in order}, labels


def candidates_for(symbol: str, market: str | None = None) -> list[str]:
    """ชื่อบน Yahoo ที่จะลองไล่ดึง — คนละตลาดเติมท้ายคนละแบบ

    เลือกจากรายชื่อในกลุ่ม → รู้ตลาดแน่นอน ใช้แบบเดียวจบ
    พิมพ์เอง (market=None) → ไล่ไทยก่อน แล้วค่อยเมกา แล้วค่อยคริปโต
    (ไทยมาก่อนเพราะชื่อย่อชนกันได้ เช่น M = MK เมืองไทย และ Macy's ที่อเมริกา)
    """
    s = symbol.upper()
    if s in INDEX_TARGETS:
        return INDEX_TARGETS[s]
    # ^GSPC / GC=F / 000001.SS — ชื่อเต็มบน Yahoo อยู่แล้ว เติมอะไรไม่ได้
    if market == "Raw" or s.startswith("^") or "=" in s or "." in s:
        return [s]
    if market == "TH":
        return [f"{s}.BK"]
    if market == "US":
        return [s]
    if market == "Crypto":
        return [s if "-" in s else f"{s}-USD"]
    return [f"{s}.BK", s, f"{s}-USD"]


def build(symbol: str, market: str | None = None):
    """คืน (figure, สัญลักษณ์ที่ใช้ได้, มี intraday ไหม) หรือ None ถ้าไม่มีข้อมูล"""
    for cand in candidates_for(symbol, market):
        daily = load_daily(cand)
        if not daily.empty and len(daily) >= 5:
            break
    else:
        return None

    # หุ้นไทยใช้แท่ง 120 นาที (วันทำการสั้น) · เมกา/คริปโตใช้ 240 นาที
    # ดูจากชื่อที่ดึงได้จริง ไม่ใช่จากกลุ่ม เพราะพิมพ์เองก็ต้องได้ถูกเหมือนกัน
    minutes = INTRADAY_MINUTES_TH if cand.upper().endswith(".BK") else INTRADAY_MINUTES_GLOBAL
    intraday = load_intraday(cand, minutes)
    panels = {
        f"{minutes}m": intraday,
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
st.session_state.setdefault("market", None)      # None = ให้ระบบเดาตลาดเอง

c1, c2, c3, c4, c5, c6 = st.columns([3.4, 1.5, 3.3, 1, 1.2, 1.1])

typed = c1.text_input("ชื่อหุ้น", key="typed", label_visibility="collapsed",
                      placeholder="พิมพ์ชื่อย่อ เช่น PTT · AAPL · BTC แล้วกด Enter")

groups, labels = symbol_groups()
group = c2.selectbox("กลุ่ม", list(groups) or ["—"], key="group",
                     label_visibility="collapsed", disabled=not groups)
names = groups.get(group, [])
placeholder = f"— เลือกจาก {group} —" if names else "— ไม่มีรายชื่อ —"
choice = c3.selectbox("หุ้นในกลุ่ม", [placeholder] + names, key="choice",
                      label_visibility="collapsed", disabled=not names,
                      format_func=lambda s: labels.get(s, s))

# ตัวไหนถูกแก้ล่าสุด ตัวนั้นชนะ
if typed != st.session_state.get("_prev_typed"):
    st.session_state._prev_typed = typed
    if typed.strip():
        st.session_state.symbol = typed.strip().upper()
        st.session_state.market = None          # พิมพ์เอง = ไม่รู้ตลาด ให้ไล่หา

if choice != st.session_state.get("_prev_choice"):
    st.session_state._prev_choice = choice
    if choice not in (placeholder, "— ไม่มีรายชื่อ —"):
        st.session_state.symbol = choice
        st.session_state.market = GROUP_MARKET.get(group)

if c4.button("SET", **FULL_BTN):
    st.session_state.symbol, st.session_state.market = "SET", None
if c5.button("SET50", **FULL_BTN):
    st.session_state.symbol, st.session_state.market = "SET50", None
if c6.button("รีเฟรช", **FULL_BTN, help="ดึงราคาใหม่ ไม่ใช้ข้อมูลที่จำไว้"):
    st.cache_data.clear()

symbol = st.session_state.symbol

st.session_state.fetch_errors = []
with st.spinner(f"กำลังดึงข้อมูล {symbol} ..."):
    result = build(symbol, st.session_state.market)

if result is None:
    st.error(f"ไม่พบข้อมูลของ **{symbol}**")
    if st.session_state.fetch_errors:
        st.warning("ดึงข้อมูลไม่สำเร็จ (คนละเรื่องกับ 'ไม่มีหุ้นตัวนี้') — "
                   "อาจเน็ตหลุดหรือติด rate limit ของ Yahoo กด **รีเฟรช** ลองใหม่อีกครั้ง")
        st.caption(" · ".join(st.session_state.fetch_errors))
    st.caption("ตรวจตัวสะกดอีกที · หุ้นไทยใส่แค่ชื่อย่อ เช่น PTT (ไม่ต้องเติม .BK) · "
               "หุ้นเมกาใส่ชื่อย่อตรง ๆ เช่น AAPL · คริปโตใส่ชื่อเหรียญ เช่น BTC หรือ BTC-USD · "
               "หุ้นที่เพิ่งเข้าตลาดหรือสภาพคล่องต่ำ Yahoo อาจยังไม่มีข้อมูล")
    st.stop()

fig, used, has_intraday = result

st.plotly_chart(fig, **FULL_CHART, config={
    "scrollZoom": True, "displaylogo": False, "responsive": True,
})

# รวมเป็นบรรทัดเดียว — ทุก px ที่ประหยัดได้ตรงนี้คือความสูงที่กราฟได้เพิ่ม
note = f"สัญลักษณ์: `{used}` · ณ {d.now_bkk():%d/%m/%Y %H:%M} น. (เวลาไทย)"
if not has_intraday:
    note += " · ไม่มี intraday ช่องแรกจึงว่าง"
note += (" · ราคาจาก Yahoo Finance เป็นข้อมูลปิดตลาด/ดีเลย์ ไม่ใช่เรียลไทม์ "
         "ใช้ประกอบการศึกษา ตรวจกับโบรกเกอร์ก่อนซื้อขาย")
st.caption(note)
