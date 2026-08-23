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
               "Crypto", "Commodity", "Index", "Bond"]

# ความยาวแท่งของช่อง intraday (นาที) — ไทยวันทำการสั้นกว่า เลยใช้แท่งถี่กว่า
INTRADAY_MINUTES_TH = 120
INTRADAY_MINUTES_GLOBAL = 240           # หุ้นเมกา + คริปโต

# กลุ่มไหนอยู่ตลาดไหน — ใช้ตัดสินว่าจะเติม .BK / -USD ให้ชื่อย่อไหม
# "Raw" = ชื่อในลิสต์เป็นชื่อบน Yahoo อยู่แล้ว (GC=F, ^GSPC) ใช้ตรง ๆ ห้ามเติมอะไร
GROUP_MARKET = {"SET50": "TH", "SET100": "TH", "mai": "TH",
                "US": "US", "Crypto": "Crypto",
                "Commodity": "Raw", "Index": "Raw", "Bond": "Raw"}

# ดัชนี: ชื่อสัญลักษณ์บน Yahoo ไม่แน่นอน ลองไล่ทีละตัวจนกว่าจะเจอข้อมูล
INDEX_TARGETS = {
    "SET": ["^SET.BK", "^SET", "^SETI"],
    "SET50": ["^SET50.BK", "^SET50", "TDEX.BK"],
}

st.set_page_config(page_title="กราฟหุ้นไทย", page_icon="📈",
                   layout="wide", initial_sidebar_state="collapsed")

# ความสูงกราฟ — ยืดตามความสูงจอจริงของเครื่องที่เปิด (iPad / มือถือ / จอคอม)
# ทำด้วย CSS ล้วน: ตั้งความสูงให้ "กล่องที่ครอบกราฟ" แล้วปล่อยให้ Plotly (responsive)
# วัดกล่องเอง — จึงหมุนจอ/ย่อขยายหน้าต่างแล้วปรับตามทันทีโดยไม่ต้อง rerun
#
# กับดักที่เจอตอนทำ (อย่ารื้อออก):
#   • ต้องส่ง height=None เข้า build_figure ด้วย ถ้าใส่ตัวเลข Plotly จะล็อกความสูงไว้
#     แล้ว responsive ไม่ทำงาน
#   • .stElementContainer ของ Streamlit ตั้ง flex: 0 0 450px ไว้ ถ้าแก้แต่ height
#     กล่องจะยัง 450 px แล้วกราฟโดนตัดครึ่ง — ต้องทับ flex-basis ด้วย
#   • ใช้ svh (ไม่ใช่ vh) เพราะ Safari บนมือถือนับแถบที่อยู่/แถบล่างต่างกัน
CHART_TOP_PX = 70                       # แถวควบคุมบน + คำอธิบายล่าง
CHART_MIN_PX = 380                      # จอเตี้ยมากก็ไม่ให้กราฟแบนกว่านี้ (ยอมให้เลื่อน)
CHART_MAX_PX = 1600

# โหมดเต็มจอ: ไทม์เฟรมเดียวเต็มหน้า — เสียความสูงให้แถวเลือกไทม์เฟรมอีกแถว
FULL_TFS = ["60m", "120m", "Day", "Week", "Month", "Quarter", "Year"]
FULL_TF_ROW_PX = 42                     # ความสูงของแถวปุ่มเลือกไทม์เฟรม

# ต้องตั้งค่าเริ่มต้นก่อนใส่ CSS เพราะความสูงกราฟขึ้นกับโหมดที่อยู่
st.session_state.setdefault("symbol", "SET")
st.session_state.setdefault("market", None)      # None = ให้ระบบเดาตลาดเอง
st.session_state.setdefault("fullscreen", False)  # True = โหมดไทม์เฟรมเดียวเต็มจอ
st.session_state.setdefault("cloud", False)       # True = เปิดริบบิ้น EMA (ปุ่ม Cloud)

# โหมดเต็มจอมีแถวปุ่มไทม์เฟรมเพิ่มมาอีกแถว ต้องหักความสูงให้ด้วย
_top_px = CHART_TOP_PX + (FULL_TF_ROW_PX if st.session_state.fullscreen else 0)
CHART_H = f"clamp({CHART_MIN_PX}px, calc(100svh - {_top_px}px), {CHART_MAX_PX}px)"

st.markdown(f"""
<style>
  header[data-testid="stHeader"], [data-testid="stToolbar"], footer {{ display: none !important; }}
  .block-container {{ padding: .35rem .6rem .1rem !important; max-width: 100% !important; }}
  [data-testid="stVerticalBlock"] {{ gap: .3rem !important; }}
  [data-testid="stCaptionContainer"] p {{ font-size: .68rem; line-height: 1.2; margin: 0; }}
  /* กล่องของ Streamlit ที่ครอบกราฟ — ต้องทับทั้ง height และ flex-basis */
  .stElementContainer:has([data-testid="stPlotlyChart"]) {{
      height: {CHART_H} !important;
      flex: 0 0 {CHART_H} !important;
      max-height: none !important;
  }}
  [data-testid="stPlotlyChart"], [data-testid="stPlotlyChart"] > div {{
      height: {CHART_H} !important;
  }}
  /* ดรอปดาวน์ยาวขึ้น — ของเดิมโชว์ได้ 7 บรรทัดพอดี กลุ่มที่ 8 (Bond) เลยตกขอบ
     จนดูเหมือนไม่มี ต้องเลื่อนในกล่องเล็ก ๆ ซึ่งบน iPad ทำยาก */
  div[role="listbox"] {{ max-height: 62vh !important; }}
  /* แถวเลือกไทม์เฟรมให้เตี้ยที่สุด ทุก px คือความสูงที่กราฟได้เพิ่ม */
  [data-testid="stRadio"] > div {{ gap: .35rem !important; }}
  [data-testid="stRadio"] label {{ margin: 0 !important; padding: 0 !important; }}
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
def _symbol_groups(stamp: float) -> tuple[dict[str, list[str]], dict[str, str]]:
    """อ่าน symbols.csv → ({กลุ่ม: [ชื่อย่อ]}, {ชื่อย่อ: ชื่อไทย})

    `stamp` = เวลาแก้ไขไฟล์ ใส่ไว้เป็นส่วนหนึ่งของคีย์ cache เฉย ๆ
    เพิ่มหุ้น/กลุ่มใหม่ในไฟล์แล้วดรอปดาวน์อัปเดตทันที ไม่ต้องรอ cache 24 ชม. หมดอายุ

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


def symbol_groups() -> tuple[dict[str, list[str]], dict[str, str]]:
    stamp = os.path.getmtime(SYMBOLS_CSV) if os.path.exists(SYMBOLS_CSV) else 0.0
    return _symbol_groups(stamp)


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


def one_panel(cand: str, tf: str, daily: pd.DataFrame) -> pd.DataFrame:
    """ข้อมูลของไทม์เฟรมเดียว (ใช้ในโหมดเต็มจอ)

    60m/120m ดึงรายชั่วโมงมารวมแท่ง · ที่เหลือย่อยจากรายวันที่ดึงมาแล้ว
    """
    if tf.endswith("m"):
        return load_intraday(cand, int(tf[:-1]))
    if tf == "Day":
        return daily
    rule = {"Week": "W-FRI", "Month": "ME", "Quarter": "QE", "Year": "YE"}[tf]
    return d.to_period(daily, rule)


def build(symbol: str, market: str | None = None, full_tf: str | None = None,
          ribbon: bool = False):
    """คืน (figure, สัญลักษณ์ที่ใช้ได้, ข้อมูลครบไหม) หรือ None ถ้าไม่มีข้อมูลเลย

    full_tf = None → กราฟ 4 จอเหมือนเดิม · ใส่ชื่อไทม์เฟรม → เต็มจอช่องเดียว
    ribbon = True → ระบายริบบิ้น EMA 10/30 ทับพื้นหลัง (ปุ่ม Cloud)
    """
    for cand in candidates_for(symbol, market):
        daily = load_daily(cand)
        if not daily.empty and len(daily) >= 5:
            break
    else:
        return None

    if full_tf:
        df = one_panel(cand, full_tf, daily)
        if df is None or df.empty:
            return (None, cand, False)
        return (d.build_single_figure(symbol.upper(), df, full_tf,
                                      height=None, ribbon=ribbon), cand, True)

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
    return (d.build_figure(symbol.upper(), panels, height=None, ribbon=ribbon),
            cand, not intraday.empty)


# ─────────────────────────────────────────────────────────────
# หน้าเว็บ
# ─────────────────────────────────────────────────────────────

c1, c2, c3, c4, c5, c6, c7, c8 = st.columns([2.7, 1.3, 2.7, .9, 1.1, 1.0, 1.1, 1.2])

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

full_label = "4 จอ" if st.session_state.fullscreen else "Full"
if c7.button(full_label, **FULL_BTN,
             help="สลับระหว่างกราฟ 4 ไทม์เฟรม กับไทม์เฟรมเดียวเต็มจอ"):
    st.session_state.fullscreen = not st.session_state.fullscreen
    st.rerun()                          # ความสูงกราฟเปลี่ยนตามโหมด ต้องวาด CSS ใหม่

# ปุ่มริบบิ้น — อยู่ถัดจากปุ่ม Full
cloud_label = "Cloud ✓" if st.session_state.cloud else "Cloud"
if c8.button(cloud_label, **FULL_BTN,
             help="ริบบิ้น EMA 10/30 — เขียว = ขาขึ้น · ชมพู = ขาลง "
                  "พร้อมป้าย B/S ตรงจุดที่ริบบิ้นเปลี่ยนสี"):
    st.session_state.cloud = not st.session_state.cloud
    st.rerun()          # ป้ายบนปุ่มวาดไปก่อนหน้านี้แล้ว ต้องวาดใหม่ให้ตรงสถานะ
                        # (ข้อมูลอยู่ใน cache อยู่แล้ว รอบใหม่จึงไม่ได้ดึง Yahoo ซ้ำ)

# แถวเลือกไทม์เฟรม — โผล่เฉพาะโหมดเต็มจอ
full_tf = None
if st.session_state.fullscreen:
    full_tf = st.radio("ไทม์เฟรม", FULL_TFS, key="full_tf",
                       index=FULL_TFS.index("Day"), horizontal=True,
                       label_visibility="collapsed")

symbol = st.session_state.symbol

st.session_state.fetch_errors = []
with st.spinner(f"กำลังดึงข้อมูล {symbol} ..."):
    result = build(symbol, st.session_state.market, full_tf,
                   ribbon=st.session_state.cloud)

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

fig, used, has_data = result

if fig is None:                     # เต็มจอ: หุ้นตัวนี้ไม่มีข้อมูลของไทม์เฟรมที่เลือก
    st.warning(f"**{used}** ไม่มีข้อมูลไทม์เฟรม **{full_tf}** — "
               "ลองเลือกไทม์เฟรมอื่น (intraday ของบางตัว Yahoo ไม่มีให้)")
    st.stop()

st.plotly_chart(fig, **FULL_CHART, config={
    "scrollZoom": True, "displaylogo": False, "responsive": True,
})

# รวมเป็นบรรทัดเดียว — ทุก px ที่ประหยัดได้ตรงนี้คือความสูงที่กราฟได้เพิ่ม
note = f"สัญลักษณ์: `{used}` · ณ {d.now_bkk():%d/%m/%Y %H:%M} น. (เวลาไทย)"
if not has_data and not full_tf:
    note += " · ไม่มี intraday ช่องแรกจึงว่าง"
note += (" · ราคาจาก Yahoo Finance เป็นข้อมูลปิดตลาด/ดีเลย์ ไม่ใช่เรียลไทม์ "
         "ใช้ประกอบการศึกษา ตรวจกับโบรกเกอร์ก่อนซื้อขาย")
st.caption(note)
