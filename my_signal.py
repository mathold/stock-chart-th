"""
โหมด My Signal — กราฟ 3 แถว
===========================
แถวบน  BBE (Bull & Bear Expert)  ริบบิ้นเขียว = ขาขึ้น · ริบบิ้นแดง = ขาลง
        + สีแท่งเทียน เหลือง=ซื้อ แดง=ขาย เขียว=ถือหุ้น ชมพู=ถือเงินสด
        + ป้าย Buy ใต้แท่งเหลือง / Sell เหนือแท่งแดง
        + ตัวเลข Pattern 49 (นับ 1-9) ฟ้า=นับขึ้น · ส้ม=นับลง
แถวกลาง DE  (Deviation Expert)    แท่งเขียว = เงินทุนไหลเข้า · แท่งแดง = ไหลออก
แถวล่าง MCD (Multicolor Dragon)   แท่ง 100%  เขียว = กำไร/รายใหญ่ · เหลือง = ลอย/รายย่อย
                                             แดง = ติดดอย    + เส้น MA10 สามเส้น

⚠️ สูตรจริงของ Homily เป็นความลับทางการค้า ไม่เคยเปิดเผย
   ไฟล์นี้ "ทำเลียนแบบ" จากพฤติกรรมที่เห็นในคู่มือ + ภาพตัวอย่าง
   สีถูกสลับเป็นแบบสากลทั้งหมด (เขียว = ขึ้น/เงินเข้า/กำไร/ซื้อ ·
   แดง = ลง/เงินออก/ติดดอย/ขาย) ซึ่งตรงข้ามกับ Homily ตัวจริงที่ใช้แบบจีน
   เทียบกับภาพจากโปรแกรมจริงต้องกลับสีในหัวก่อน
   โดยใช้เฉพาะข้อมูลที่ Yahoo ให้ (OHLCV) เท่านั้น ตัวเลขจึงไม่ตรงกับของ Homily
   โดยเฉพาะ MCD ที่ของจริงแยก "รายใหญ่/รายย่อย" จากขนาดคำสั่งซื้อขายรายไม้
   ซึ่งเราไม่มี — ที่นี่จึงแยกเป็น "กำไร/ลอย/ติดดอย" จากราคาทุนแทน

แก้ค่าต่าง ๆ ที่หัวไฟล์นี้ไฟล์เดียว
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots

import thai_stock_dashboard as d

# ─────────────────────────────────────────────────────────────
# ค่าที่ปรับได้
# ─────────────────────────────────────────────────────────────

BARS = 160                      # จำนวนแท่งต่อช่อง (โหมด 4 จอ) — น้อยกว่าโหมดปกติ
BARS_FULL = 320                 # โหมดเต็มจอ                      เพราะมี 3 แถวซ้อน

# ── BBE ── ริบบิ้นสองเส้น EMA ซ้อนสองชั้น (double EMA) ให้เส้นลื่นและริบบิ้นหนา
BBE_FAST, BBE_SLOW = 13, 34
# ทึบแค่ ~0.7 ตั้งใจ — แท่งเทียน "ถือหุ้น" เป็นเขียวสว่าง ถ้าริบบิ้นเขียวจัดเท่ากัน
# ตอนราคาย่อลงมาทับริบบิ้นจะกลืนกันจนแยกไม่ออก
BBE_UP = "rgba(0,190,80,0.70)"      # เขียว = ขาขึ้น
BBE_DOWN = "rgba(214,20,20,0.72)"   # แดง  = ขาลง
BBE_EDGE = "#FFD24A"                # เส้นขอบบางสีเหลืองแบบในภาพตัวอย่าง

# ── สีแท่งเทียน (Signal Aditor) ──
# Homily ตัวจริงใช้ แดง=ซื้อ เหลือง=ขาย น้ำเงิน=ถือหุ้น ฟ้า=ถือเงินสด (แบบจีน)
# ที่นี่ปรับเป็น เหลือง=ซื้อ แดง=ขาย เขียว=ถือหุ้น ชมพู=ถือเงินสด
SIG_BUY = "#FFE800"             # เหลือง     = สัญญาณซื้อ
SIG_SELL = "#FF3B3B"            # แดงสว่าง   = สัญญาณขาย
SIG_HOLD = "#00FF7F"            # เขียวสว่าง = ถือหุ้นต่อ
SIG_CASH = "#FF7BD5"            # ชมพู       = ถือเงินสด

# ป้าย Buy / Sell ที่แปะบนแท่งสัญญาณ
SIG_MARK_SIZE = 10              # ขนาดตัวอักษร
SIG_MARK_PAD = 0.055            # ระยะห่างจากแท่ง คิดเป็นสัดส่วนของช่วงราคาที่เห็นในจอ
                                # ใช้สัดส่วนของช่วงราคา ไม่ใช่ % ของราคา เพราะหุ้น 2 บาท
                                # กับหุ้น 250 บาท ต้องได้ระยะห่างที่ตาเห็นเท่ากัน

# ── Pattern 49 ── นับแท่งเทียบกับ 4 แท่งก่อนหน้า ครบ 9 แล้วเริ่มใหม่
P49_LOOKBACK, P49_TARGET = 4, 9
P49_UP_COLOR = "#00E5FF"        # ฟ้า  = นับฝั่งขึ้น (อยู่เหนือแท่ง)
                                # ย้ายจากชมพูเพราะชมพูไปเป็นแท่ง "ถือเงินสด" แล้ว
P49_DOWN_COLOR = "#FF9A2E"      # ส้ม  = นับฝั่งลง  (อยู่ใต้แท่ง)
                                # ไม่ใช้เขียวแล้ว เพราะทั้งจอเขียว = ขาขึ้น
                                # เลขเขียวใต้แท่งขาลงจะอ่านสวนความหมาย

# ── DE ── ผลต่างของราคาถ่วงน้ำหนักด้วยวอลุ่ม เร็ว-ช้า
DE_FAST, DE_SLOW, DE_SMOOTH = 13, 55, 5
DE_IN = "#00E000"               # เขียว = เงินทุนไหลเข้า (ค่ากำลังขึ้น)
DE_OUT = "#FF2A2A"              # แดง   = เงินทุนไหลออก  (ค่ากำลังลง)
DE_ZERO = "#E8D200"             # เส้น 0 สีเหลือง

# ── MCD ── กระจายต้นทุน (chip distribution)
MCD_LEVELS = 120                # จำนวนช่องราคาที่ใช้เก็บต้นทุน
MCD_BAND = 0.08                 # ±8% รอบราคาปัจจุบัน = ช่วง "ลอย" (เหลือง)
MCD_TURNOVER = 0.015            # อัตราเปลี่ยนมือฐาน ยิ่งมากยิ่งลืมอดีตเร็ว
MCD_MA = 10                     # คาบเส้นค่าเฉลี่ยสามเส้น
MCD_PROFIT = "#00C000"          # เขียว  = ต้นทุนต่ำกว่าราคา (กำไร / รายใหญ่)
MCD_FLOAT = "#FFE800"           # เหลือง = ต้นทุนใกล้ราคา   (ลอย / รายย่อย)
MCD_TRAP = "#E00000"            # แดง    = ต้นทุนสูงกว่าราคา (ติดดอย)
MCD_MA_PROFIT = "#B060FF"       # ม่วง  ตามแท่ง "กำไร"  (ล่างสุด)
MCD_MA_FLOAT = "#FF63C8"        # ชมพู  ตามแท่ง "ลอย"   (ตรงกลาง)
MCD_MA_TRAP = "#00C8FF"         # ฟ้า   ตามแท่ง "ติดดอย" (บนสุด)

# ── ธีมดำ ──
BG = "#000000"
GRID = "#333333"
TXT = "#FFFFFF"
AXIS_FONT = 10.5


# ─────────────────────────────────────────────────────────────
# อินดิเคเตอร์
# ─────────────────────────────────────────────────────────────

def _dema(s: pd.Series, n: int) -> pd.Series:
    """EMA ซ้อนสองชั้น — เส้นลื่นกว่า EMA ธรรมดา ริบบิ้นเลยไม่หยัก"""
    return d.ema(d.ema(s, n), n)


def bbe(close: pd.Series) -> tuple[pd.Series, pd.Series]:
    """ริบบิ้น BBE — คืน (เส้นเร็ว, เส้นช้า) · เร็วอยู่บน = ขาขึ้น (เขียว)"""
    return _dema(close, BBE_FAST), _dema(close, BBE_SLOW)


def _keep_runs(cnt: np.ndarray) -> np.ndarray:
    """เก็บเฉพาะรอบที่นับครบ 9 กับรอบที่ยังนับค้างอยู่ที่แท่งล่าสุด

    ถ้าโชว์ทุกรอบ ตัวเลขจะเต็มกราฟจนอ่านไม่ออก — Homily เองก็โชว์เฉพาะ
    รอบที่มีความหมาย รอบที่นับได้ 2-3 แท่งแล้วขาดไม่ต้องสนใจ
    """
    out = np.zeros_like(cnt)
    n = len(cnt)
    i = 0
    while i < n:
        if cnt[i] == 0:
            i += 1
            continue
        j = i + 1                       # รอบหนึ่งเริ่มที่เลข 1 จบก่อนเลข 1 ตัวถัดไป
        while j < n and cnt[j] != 0 and cnt[j] != 1:
            j += 1
        seg = cnt[i:j]
        if seg.max() >= P49_TARGET or j >= n:
            out[i:j] = seg
        i = j
    return out


def pattern49(close: pd.Series) -> tuple[pd.Series, pd.Series]:
    """นับ 1-9 แบบ Pattern 49 — คืน (นับฝั่งขึ้น, นับฝั่งลง) · 0 = ไม่โชว์

    ฝั่งขึ้น : ราคาปิดสูงกว่าปิดของ 4 แท่งก่อน → นับต่อ ไม่งั้นล้างเป็น 0
    ครบ 9 แล้วเริ่มนับใหม่ (เลข 1 = จุดเริ่มรอบใหม่ = จุดซื้อตามคู่มือ)
    """
    up = np.zeros(len(close), dtype=int)
    dn = np.zeros(len(close), dtype=int)
    c = close.to_numpy(dtype=float)
    for i in range(P49_LOOKBACK, len(c)):
        if c[i] > c[i - P49_LOOKBACK]:
            up[i] = 1 if up[i - 1] >= P49_TARGET else up[i - 1] + 1
        if c[i] < c[i - P49_LOOKBACK]:
            dn[i] = 1 if dn[i - 1] >= P49_TARGET else dn[i - 1] + 1
    return (pd.Series(_keep_runs(up), index=close.index),
            pd.Series(_keep_runs(dn), index=close.index))


def de(df: pd.DataFrame) -> pd.DataFrame:
    """DE — เงินทุนไหลเข้า/ออก วาดเป็นแท่งเทียนรอบเส้น 0

    ใช้ผลต่างของ "ราคาถ่วงน้ำหนักด้วยวอลุ่ม" เร็ว-ช้า → ได้คลื่นลื่น ๆ
    ที่ขยับตามทั้งราคาและปริมาณเงิน (ตัวที่ไม่มีวอลุ่ม เช่น ^TNX จะถอยไปใช้ราคาล้วน)

    สีแท่ง : ค่ากำลังขึ้น = แดง (ไหลเข้า) · กำลังลง = เขียว (ไหลออก)
    ไส้     : ยาวตามความเร็วที่ค่าเปลี่ยน — ตรงกับคู่มือที่ว่า "ไส้ยาว = เงินเคลื่อนแรง"
    """
    close = df["Close"].astype(float)
    vol = df["Volume"].fillna(0).astype(float)

    if vol.sum() > 0:
        def vwma(n: int) -> pd.Series:
            num = (close * vol).rolling(n, min_periods=1).sum()
            den = vol.rolling(n, min_periods=1).sum()
            # ช่วงที่วอลุ่มเป็นศูนย์ยกแผง (วันหยุดยาว) ให้ถอยไปใช้ราคาเฉลี่ยธรรมดา
            return (num / den.replace(0, np.nan)).fillna(
                close.rolling(n, min_periods=1).mean())
    else:
        def vwma(n: int) -> pd.Series:
            return close.rolling(n, min_periods=1).mean()

    line = d.ema(vwma(DE_FAST) - vwma(DE_SLOW), DE_SMOOTH)
    prev = line.shift(1).fillna(line)
    # ไส้ยาวตามความเร็วที่ค่าเปลี่ยน + พื้นขั้นต่ำเล็กน้อยเทียบแอมพลิจูดทั้งเส้น
    # ไม่งั้นช่วงที่ค่านิ่งจะเหลือแต่จุดเล็ก ๆ มองไม่เห็นว่าแท่งสีอะไร
    span = float(line.max() - line.min()) if len(line) else 0.0
    speed = ((line - prev).abs().rolling(3, min_periods=1).mean()
             + max(span, 0.0) * 0.006)

    out = pd.DataFrame(index=df.index)
    out["Open"] = prev
    out["Close"] = line
    out["High"] = np.maximum(prev, line) + speed
    out["Low"] = np.minimum(prev, line) - speed
    out["Up"] = line >= prev
    return out


def mcd(df: pd.DataFrame) -> pd.DataFrame:
    """MCD — กระจายต้นทุนผู้ถือหุ้น คืน % สามกลุ่มที่รวมกันได้ 100

    วิธีคิด (แบบเดียวกับ chip distribution ของโปรแกรมจีน):
      ทุกแท่ง  ต้นทุนเก่าถูกล้างไปตามอัตราเปลี่ยนมือ  แล้วเติมต้นทุนใหม่
      กระจายเท่า ๆ กันในช่วง Low-High ของแท่งนั้น
    จากนั้นแบ่งตามราคาปัจจุบัน (MCD_BAND = ครึ่งความกว้างของช่วง "ลอย")
      ต่ำกว่าราคามาก = กำไร   (เขียว · วางล่างสุด)
      ใกล้ราคา       = ลอย    (เหลือง · ตรงกลาง)
      สูงกว่าราคามาก = ติดดอย (แดง · บนสุด)
    ขอบระหว่างกลุ่มไล่ระดับ ไม่ได้ตัดคม

    อัตราเปลี่ยนมือจริงต้องใช้จำนวนหุ้นหมุนเวียนซึ่ง Yahoo ไม่ได้ให้ทุกตัว
    จึงประมาณจาก "วอลุ่มวันนี้เทียบวอลุ่มเฉลี่ย" แทน
    """
    n = len(df)
    idx = df.index

    def _out(p, f, l) -> pd.DataFrame:
        """ประกอบผลลัพธ์ + เส้นค่าเฉลี่ย — ทุกทางออกต้องผ่านตรงนี้
        ไม่งั้นเคสขอบ (ข้อมูลว่าง/ราคาคงที่) จะคืน DataFrame ที่ไม่มีคอลัมน์ MA
        """
        out = pd.DataFrame({"P": p, "F": f, "L": l}, index=idx)
        for k, ma in (("P", "PMA"), ("F", "FMA"), ("L", "LMA")):
            out[ma] = out[k].rolling(MCD_MA, min_periods=1).mean()
        return out

    if n == 0:
        return _out([], [], [])

    high = df["High"].to_numpy(dtype=float)
    low = df["Low"].to_numpy(dtype=float)
    close = df["Close"].to_numpy(dtype=float)
    vol = df["Volume"].fillna(0).to_numpy(dtype=float)
    if vol.sum() <= 0:                      # ดัชนี/พันธบัตรที่ไม่มีวอลุ่ม
        vol = np.ones(n)

    avg = pd.Series(vol).rolling(60, min_periods=1).mean().to_numpy()
    turn = np.clip(MCD_TURNOVER * vol / np.where(avg > 0, avg, 1), 0.005, 0.20)

    lo, hi = float(np.nanmin(low)), float(np.nanmax(high))
    if not np.isfinite(lo) or not np.isfinite(hi) or hi <= lo:
        # ราคาไม่ขยับเลย (หุ้น SP / ข้อมูลเสีย) — ต้นทุนทุกคนเท่าราคา = ลอยทั้งหมด
        return _out(0.0, 100.0, 0.0)
    pad = (hi - lo) * 0.02
    edges = np.linspace(lo - pad, hi + pad, MCD_LEVELS + 1)
    mid = (edges[:-1] + edges[1:]) / 2

    chips = np.zeros(MCD_LEVELS)
    p_pct = np.zeros(n)
    f_pct = np.zeros(n)
    l_pct = np.zeros(n)

    for i in range(n):
        # แท่งนี้กินช่องราคาไหนบ้าง — กระจายวอลุ่มเท่า ๆ กันในช่วง Low-High
        a = np.searchsorted(edges, low[i], side="right") - 1
        b = np.searchsorted(edges, high[i], side="left")
        a = max(a, 0)
        b = min(max(b, a + 1), MCD_LEVELS)

        chips *= (1 - turn[i])
        chips[a:b] += vol[i] * turn[i] / (b - a)

        total = chips.sum()
        if total <= 0:
            p_pct[i] = f_pct[i] = l_pct[i] = np.nan
            continue
        # ไล่ระดับแทนการตัดคม ๆ ที่ขอบแถบ — ถ้าตัดคมราคาขยับนิดเดียว
        # ต้นทุนก้อนใหญ่จะกระโดดข้ามกลุ่มทีเดียว แท่งเลยกระตุกเป็นฟันปลา
        w = close[i] * MCD_BAND
        w_p = np.clip((close[i] - mid) / w, 0.0, 1.0)
        w_l = np.clip((mid - close[i]) / w, 0.0, 1.0)
        p_pct[i] = float(chips @ w_p) / total * 100
        l_pct[i] = float(chips @ w_l) / total * 100
        f_pct[i] = 100 - p_pct[i] - l_pct[i]

    return _out(p_pct, f_pct, l_pct)


def signal_colors(bull: pd.Series, de_line: pd.Series) -> pd.Series:
    """สีแท่งเทียนแบบ Signal Aditor

    เหลือง ซื้อ      = ริบบิ้นกลับเป็นเขียว หรือ DE ตัดขึ้นเหนือ 0 ตอนริบบิ้นเขียว
    แดง    ขาย      = ริบบิ้นกลับเป็นแดง  หรือ DE ตัดลงใต้ 0 ตอนริบบิ้นเขียว
    เขียว  ถือหุ้นต่อ = ริบบิ้นเขียวช่วงอื่น
    ชมพู   ถือเงินสด = ริบบิ้นแดงช่วงอื่น

    อ่านง่าย ๆ: เหลือง/แดง = แท่งที่ต้องลงมือ · เขียว/ชมพู = แท่งที่ไม่ต้องทำอะไร
    """
    # .astype(bool) สำคัญมาก — shift() ทำให้ Series กลายเป็น object dtype แล้ว
    # เครื่องหมาย ~ จะไปทำ bitwise not ของ Python bool (~True = -2 ซึ่งเป็นจริง)
    # มาสก์เลยเพี้ยนทั้งชุดโดยไม่ error ให้เห็น
    bull = bull.astype(bool)
    prev_bull = bull.shift(1).fillna(bull.iloc[0] if len(bull) else False).astype(bool)
    cross_up = ((de_line > 0) & (de_line.shift(1) <= 0)).astype(bool)
    cross_dn = ((de_line < 0) & (de_line.shift(1) >= 0)).astype(bool)

    out = pd.Series(SIG_CASH, index=bull.index)
    out[bull] = SIG_HOLD
    out[bull & cross_up] = SIG_BUY
    out[bull & cross_dn] = SIG_SELL
    out[bull & ~prev_bull] = SIG_BUY
    out[~bull & prev_bull] = SIG_SELL
    return out


# ─────────────────────────────────────────────────────────────
# วาดกราฟ
# ─────────────────────────────────────────────────────────────

PANEL_POS = [(1, 1), (1, 2), (4, 1), (4, 2)]    # แถวเริ่มต้นของแต่ละช่อง


def _readout(fig, text: str, row: int, col: int, size: float = 9.0):
    fig.add_annotation(
        xref="x domain", yref="y domain", x=0.004, y=0.99,
        xanchor="left", yanchor="top", align="left",
        text=text, showarrow=False, font=dict(size=size, color=TXT),
        bgcolor="rgba(0,0,0,0.86)", borderpad=1.5, row=row, col=col,
    )


def _tag(fig, value, color: str, row: int, col: int, digits: int = 2):
    if value is None or pd.isna(value):
        return
    fig.add_annotation(
        xref="x domain", yref="y", x=1.008, y=float(value),
        xanchor="left", yanchor="middle",
        text=f" {d.fmt(value, digits)} ", showarrow=False,
        font=dict(size=9.5, color="#000000"), bgcolor=color, borderpad=2,
        row=row, col=col,
    )


def _draw_ribbon(fig, fast: pd.Series, slow: pd.Series, x: list[str],
                 row: int, col: int) -> bool | None:
    """ระบายพื้นที่ระหว่างสองเส้น เขียวตอนเร็วอยู่บน แดงตอนเร็วอยู่ล่าง

    ต้องวาดก่อนแท่งเทียนเสมอ ไม่งั้นพื้นสีจะทับแท่ง
    """
    bull = (fast >= slow).to_numpy()
    if len(bull) < 2:
        return None

    breaks = [0] + [i for i in range(1, len(bull)) if bull[i] != bull[i - 1]] + [len(bull)]
    for a, b in zip(breaks[:-1], breaks[1:]):
        lo = max(a - 1, 0)
        xs = x[lo:b]
        if len(xs) < 2:
            continue
        fill = BBE_UP if bull[a] else BBE_DOWN
        fig.add_trace(go.Scatter(x=xs, y=slow.iloc[lo:b], mode="lines",
                                 line=dict(width=0.8, color=BBE_EDGE),
                                 showlegend=False, hoverinfo="skip"),
                      row=row, col=col)
        fig.add_trace(go.Scatter(x=xs, y=fast.iloc[lo:b], mode="lines",
                                 fill="tonexty", fillcolor=fill,
                                 line=dict(width=0.8, color=BBE_EDGE),
                                 showlegend=False, hoverinfo="skip"),
                      row=row, col=col)
    return bool(bull[-1])


def _draw_signal_marks(fig, df: pd.DataFrame, x: list[str], row: int, col: int):
    """ป้าย Buy / Sell บนแท่งที่มีสัญญาณ

    Buy อยู่ใต้แท่งเหลือง · Sell อยู่เหนือแท่งแดง — วางไกลกว่าเลข Pattern 49
    เล็กน้อยเพื่อไม่ให้ตัวหนังสือทับกัน
    """
    span = float(df["High"].max() - df["Low"].min())
    if not np.isfinite(span) or span <= 0:
        span = float(df["Close"].iloc[-1]) * 0.1 if len(df) else 1.0
    pad = span * SIG_MARK_PAD

    for sig_color, label, price_key, sign, place in (
            (SIG_BUY, "Buy", "Low", -1, "bottom center"),
            (SIG_SELL, "Sell", "High", +1, "top center")):
        m = (df["_SIG"] == sig_color).to_numpy()
        if not m.any():
            continue
        idx = np.flatnonzero(m)
        fig.add_trace(go.Scatter(
            x=[x[i] for i in idx],
            y=df[price_key].to_numpy()[idx] + sign * pad,
            mode="text", text=[f"<b>{label}</b>"] * len(idx),
            textposition=place,
            textfont=dict(size=SIG_MARK_SIZE, color=sig_color),
            showlegend=False, hoverinfo="skip",
        ), row=row, col=col)


def _draw_p49(fig, df: pd.DataFrame, x: list[str], row: int, col: int):
    """ตัวเลข 1-9 — ฝั่งขึ้นอยู่เหนือแท่ง (ชมพู) · ฝั่งลงอยู่ใต้แท่ง (เขียว)"""
    for key, color, price_key, pad, place in (
            ("_P49U", P49_UP_COLOR, "High", 1.004, "top center"),
            ("_P49D", P49_DOWN_COLOR, "Low", 0.996, "bottom center")):
        m = df[key] > 0
        if not m.any():
            continue
        sub = df[m]
        fig.add_trace(go.Scatter(
            x=[x[i] for i in np.flatnonzero(m.to_numpy())],
            y=sub[price_key] * pad, mode="text",
            text=[f"<b>{v}</b>" if v == P49_TARGET else str(v) for v in sub[key]],
            textposition=place,
            textfont=dict(size=[12.5 if v == P49_TARGET else 9.5 for v in sub[key]],
                          color=color),
            showlegend=False, hoverinfo="skip",
        ), row=row, col=col)


def draw_panel(fig, src: pd.DataFrame, tf: str, base_row: int, col: int,
               bars: int = BARS):
    """วาดหนึ่งช่อง = 3 แถว (BBE / DE / MCD)"""
    df = src.copy()
    df["_F"], df["_S"] = bbe(df["Close"])
    df["_P49U"], df["_P49D"] = pattern49(df["Close"])

    ded = de(df)
    mcdd = mcd(df)
    df["_SIG"] = signal_colors(df["_F"] >= df["_S"], ded["Close"])

    df = df.tail(bars)
    ded = ded.tail(bars)
    mcdd = mcdd.tail(bars)
    x = d.label_axis(df.index, tf)

    # ── แถว 1: BBE ────────────────────────────────────────────
    bull = _draw_ribbon(fig, df["_F"], df["_S"], x, base_row, col)

    # Plotly ใส่สีรายแท่งใน Candlestick ไม่ได้ — แยกเป็น trace ละสีแทน
    for color, name in ((SIG_BUY, "ซื้อ"), (SIG_SELL, "ขาย"),
                        (SIG_HOLD, "ถือหุ้น"), (SIG_CASH, "ถือเงินสด")):
        m = df["_SIG"] == color
        if not m.any():
            continue
        fig.add_trace(go.Candlestick(
            x=x, open=df["Open"].where(m), high=df["High"].where(m),
            low=df["Low"].where(m), close=df["Close"].where(m),
            increasing=dict(line=dict(color=color, width=1), fillcolor=color),
            decreasing=dict(line=dict(color=color, width=1), fillcolor=color),
            name=name, showlegend=False, hoverinfo="x+y",
        ), row=base_row, col=col)

    _draw_p49(fig, df, x, base_row, col)
    _draw_signal_marks(fig, df, x, base_row, col)

    # ── แถว 2: DE ─────────────────────────────────────────────
    for up, color in ((True, DE_IN), (False, DE_OUT)):
        m = ded["Up"] == up
        if not m.any():
            continue
        fig.add_trace(go.Candlestick(
            x=x, open=ded["Open"].where(m), high=ded["High"].where(m),
            low=ded["Low"].where(m), close=ded["Close"].where(m),
            increasing=dict(line=dict(color=color, width=1), fillcolor=color),
            decreasing=dict(line=dict(color=color, width=1), fillcolor=color),
            name="DE", showlegend=False, hoverinfo="skip",
        ), row=base_row + 1, col=col)
    fig.add_hline(y=0, line=dict(color=DE_ZERO, width=1),
                  row=base_row + 1, col=col)

    # ── แถว 3: MCD ────────────────────────────────────────────
    for key, color in (("P", MCD_PROFIT), ("F", MCD_FLOAT), ("L", MCD_TRAP)):
        fig.add_trace(go.Bar(
            x=x, y=mcdd[key], marker_color=color, marker_line_width=0,
            name=key, showlegend=False, hoverinfo="skip",
        ), row=base_row + 2, col=col)
    for key, color in (("PMA", MCD_MA_PROFIT), ("FMA", MCD_MA_FLOAT),
                       ("LMA", MCD_MA_TRAP)):
        fig.add_trace(go.Scatter(
            x=x, y=mcdd[key], mode="lines", line=dict(color=color, width=1.4),
            name=key, showlegend=False, hoverinfo="skip",
        ), row=base_row + 2, col=col)

    # ── ตัวเลขหัวแถว ──────────────────────────────────────────
    last = df.iloc[-1]
    prev_close = df["Close"].iloc[-2] if len(df) > 1 else last["Close"]
    pct = (last["Close"] / prev_close - 1) * 100 if prev_close else 0.0
    trend_color = "#00D060" if bull else "#FF4040"
    trend_word = "ริบบิ้นเขียว = ขาขึ้น" if bull else "ริบบิ้นแดง = ขาลง"
    cnt = (f'  <span style="color:{P49_UP_COLOR}">นับขึ้น {int(last["_P49U"])}</span>'
           if last["_P49U"] else
           (f'  <span style="color:{P49_DOWN_COLOR}">นับลง {int(last["_P49D"])}</span>'
            if last["_P49D"] else ""))
    _readout(fig, f'<b>{tf}  BBE</b>  O {d.fmt(last["Open"])}  H {d.fmt(last["High"])}  '
                  f'L {d.fmt(last["Low"])}  C {d.fmt(last["Close"])}  {pct:+.2f}%<br>'
                  f'<span style="color:{trend_color}"><b>{trend_word}</b></span>{cnt}',
             base_row, col)
    _tag(fig, last["Close"], trend_color, base_row, col)

    de_last = ded["Close"].iloc[-1]
    de_color = DE_IN if bool(ded["Up"].iloc[-1]) else DE_OUT
    de_word = "เงินทุนไหลเข้า" if bool(ded["Up"].iloc[-1]) else "เงินทุนไหลออก"
    _readout(fig, f'<b>DE</b> <span style="color:{de_color}">{d.fmt(de_last, 3)}  '
                  f'{de_word}</span>', base_row + 1, col, size=8.5)

    m = mcdd.iloc[-1]
    _readout(fig, f'<b>MCD</b> '
                  f'<span style="color:{MCD_PROFIT}">กำไร {d.fmt(m["P"], 1)}%</span>  '
                  f'<span style="color:{MCD_FLOAT}">ลอย {d.fmt(m["F"], 1)}%</span>  '
                  f'<span style="color:{MCD_TRAP}">ติดดอย {d.fmt(m["L"], 1)}%</span>',
             base_row + 2, col, size=8.5)


def build_figure(ticker: str, panels: dict[str, pd.DataFrame],
                 height: int | None = None) -> go.Figure:
    """โหมด 4 จอ — สี่ไทม์เฟรม ช่องละ 3 แถว"""
    fig = make_subplots(
        rows=6, cols=2,
        row_heights=[0.20, 0.07, 0.07, 0.20, 0.07, 0.07],
        vertical_spacing=0.026, horizontal_spacing=0.085,
    )
    for i, (tf, df) in enumerate(panels.items()):
        if i >= len(PANEL_POS):
            break
        # ช่อง Month/Quarter ของหุ้นที่ข้อมูลสั้นอาจมีไม่กี่สิบแท่ง — ยังวาดได้
        # (อินดิเคเตอร์ทุกตัวใช้ min_periods=1) แค่ตัดเคสที่สั้นจนไม่มีความหมาย
        if df is None or df.empty or len(df) < 12:
            continue
        base_row, col = PANEL_POS[i]
        draw_panel(fig, df, tf, base_row, col)

    for base_row, col, anchor in ((1, 1, "x"), (1, 2, "x2"), (4, 1, "x7"), (4, 2, "x8")):
        for offset in (1, 2):
            fig.update_xaxes(matches=anchor, row=base_row + offset, col=col)
        for offset in (0, 1):
            fig.update_xaxes(showticklabels=False, row=base_row + offset, col=col)

    _style(fig, ticker, height, [(r + 2, c) for r, c in PANEL_POS])
    return fig


def build_single_figure(ticker: str, df: pd.DataFrame, tf: str,
                        height: int | None = None) -> go.Figure:
    """โหมดเต็มจอ — ไทม์เฟรมเดียว 3 แถวเต็มหน้า"""
    fig = make_subplots(rows=3, cols=1, row_heights=[0.62, 0.19, 0.19],
                        vertical_spacing=0.02)
    if df is not None and not df.empty and len(df) >= 12:
        draw_panel(fig, df, tf, 1, 1, bars=BARS_FULL)

    for offset in (1, 2):
        fig.update_xaxes(matches="x", row=1 + offset, col=1)
    for offset in (0, 1):
        fig.update_xaxes(showticklabels=False, row=1 + offset, col=1)

    fig.update_xaxes(nticks=12)
    _style(fig, ticker, height, [(3, 1)])
    fig.update_yaxes(tickfont=dict(size=AXIS_FONT + 1.5, color=TXT))
    return fig


def _style(fig: go.Figure, ticker: str, height: int | None,
           mcd_rows: list[tuple[int, int]]) -> None:
    fig.update_xaxes(type="category", nticks=7, rangeslider_visible=False,
                     showgrid=True, gridcolor=GRID, zeroline=False,
                     tickangle=0, tickfont=dict(size=9, color=TXT))
    fig.update_yaxes(showgrid=True, gridcolor=GRID, zeroline=False,
                     tickfont=dict(size=AXIS_FONT, color=TXT),
                     side="right", ticklabelposition="outside")
    # แถว MCD เป็น % รวม 100 เสมอ ล็อกสเกลไว้เลยจะได้เทียบข้ามช่องได้
    for row, col in mcd_rows:
        fig.update_yaxes(range=[0, 100], dtick=50, row=row, col=col)

    fig.update_layout(
        title=dict(text=f"{ticker}  ·  My Signal  ·  {d.now_bkk():%d/%m/%Y %H:%M}",
                   x=0.01, font=dict(size=15, color=TXT)),
        height=height, autosize=True,
        paper_bgcolor=BG, plot_bgcolor=BG,
        font=dict(family="Arial, sans-serif", size=11, color=TXT),
        margin=dict(l=14, r=80, t=52, b=8),
        showlegend=False,
        hovermode="x unified", dragmode="pan",
        # แท่ง MCD ต้องชิดกันเป็นแผงทึบแบบในภาพตัวอย่าง เว้นช่องมากจะเห็นเป็นริ้วดำ
        barmode="stack", bargap=0.02,
    )
