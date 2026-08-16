"""
Thai Stock 4-Panel Dashboard
============================
สร้างไฟล์ HTML กราฟ 2x2 (สี่ไทม์เฟรมของหุ้นตัวเดียว) สำหรับเปิดดูบน iPad

ไทม์เฟรม : 120 นาที / Day / Week / Month
แต่ละช่อง : แท่งเทียน + EMA 5,10,25,50,75,200 / RSI(7) / MACD(12,26,9)

วิธีใช้
-------
    pip install yfinance pandas plotly
    python thai_stock_dashboard.py

ไฟล์ผลลัพธ์จะถูกเซฟไว้ที่ OUTPUT_DIR แล้วเปิดจาก iPad ได้เลย
"""

from __future__ import annotations

import os
from datetime import datetime

import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots

# ─────────────────────────────────────────────────────────────
# ตั้งค่า — แก้ตรงนี้ที่เดียวพอ
# ─────────────────────────────────────────────────────────────

TICKERS = ["PTT.BK", "KBANK.BK"]      # ใส่กี่ตัวก็ได้ ได้ไฟล์ละตัว (หุ้นไทยต้องมี .BK ต่อท้าย)

BARS = 200                             # จำนวนแท่งที่แสดงต่อหนึ่งช่อง
CHART_HEIGHT = 1000                    # ความสูงรวม (px) ของไฟล์ HTML
                                       # ฝั่งเว็บ Streamlit ส่ง height=None แล้วคุมด้วย CSS ให้เต็มจอแทน
OUTPUT_DIR = os.path.expanduser("~/StockCharts")

EMA_STYLE = {                          # คาบ : (สี, ความหนาเส้น)
    5:   ("#00A651", 1.2),             # เขียว
    10:  ("#E23B3B", 1.2),             # แดง
    25:  ("#00A8E8", 1.4),             # ฟ้า
    50:  ("#E8A800", 1.4),             # เหลือง (เข้มลงนิดเพื่อให้เห็นบนพื้นขาว)
    75:  ("#FF69B4", 1.4),             # ชมพู
    200: ("#000000", 1.8),             # ดำ
}

RSI_PERIOD = 7
RSI_COLOR = "#E8A800"                  # เหลือง
RSI_LEVELS = {                         # ระดับ : สีเส้นประ
    30: "#FF69B4",                     # ชมพู
    50: "#FF8C00",                     # ส้ม
    70: "#00A651",                     # เขียว
}
MACD_FAST, MACD_SLOW, MACD_SIGNAL = 12, 26, 9
MACD_LINE_COLOR = "#1F4EDD"            # น้ำเงิน
MACD_SIGNAL_COLOR = "#E23B3B"          # แดง

UP_COLOR, DOWN_COLOR = "#00A651", "#E23B3B"
BG_COLOR = "#FFFFFF"
GRID_COLOR = "#ECECEC"

TIMEFRAMES = ["120m", "Day", "Week", "Month"]   # ลำดับ: ซ้ายบน, ขวาบน, ซ้ายล่าง, ขวาล่าง


# ─────────────────────────────────────────────────────────────
# ดึงข้อมูล
# ─────────────────────────────────────────────────────────────

def _flatten(df: pd.DataFrame) -> pd.DataFrame:
    """yfinance รุ่นใหม่คืนคอลัมน์แบบ MultiIndex — ทำให้แบนก่อน"""
    if isinstance(df.columns, pd.MultiIndex):
        df = df.droplevel(1, axis=1)
    df.columns = [str(c).title() for c in df.columns]
    # Yahoo มักแถมแท่งของวันปัจจุบันที่ยังไม่มีราคาปิดมาด้วย (Close = NaN)
    # ตัดทิ้งก่อน ไม่งั้นแท่งสุดท้ายจะว่างและตัวเลข %/อินดิเคเตอร์กลายเป็น nan
    return df[["Open", "High", "Low", "Close", "Volume"]].dropna(subset=["Close"])


def fetch_intraday(ticker: str) -> pd.DataFrame:
    """ดึงรายชั่วโมงแล้วรวมเป็นแท่ง 120 นาที

    หมายเหตุตลาดไทย: พักเที่ยง 12:30-14:30 ทำให้แท่ง 120 นาทีบางแท่ง
    กินเวลาไม่เต็ม (เช่น 12:00-12:30) — เป็นเรื่องปกติของการรวมแท่ง
    """
    import yfinance as yf

    df = yf.download(ticker, period="730d", interval="60m",
                     auto_adjust=False, progress=False)
    if df.empty:
        return df
    df = _flatten(df)

    if df.index.tz is not None:
        df.index = df.index.tz_convert("Asia/Bangkok")

    return df.resample("120min", origin="start_day").agg({
        "Open": "first", "High": "max", "Low": "min",
        "Close": "last", "Volume": "sum",
    }).dropna(subset=["Close"])


def fetch_daily(ticker: str) -> pd.DataFrame:
    """ดึงรายวันย้อนหลังยาว ๆ ไว้ใช้ทำ Day / Week / Month"""
    import yfinance as yf

    df = yf.download(ticker, period="20y", interval="1d",
                     auto_adjust=False, progress=False)
    return _flatten(df) if not df.empty else df


def to_period(daily: pd.DataFrame, rule: str) -> pd.DataFrame:
    return daily.resample(rule).agg({
        "Open": "first", "High": "max", "Low": "min",
        "Close": "last", "Volume": "sum",
    }).dropna(subset=["Close"])


# ─────────────────────────────────────────────────────────────
# อินดิเคเตอร์
# ─────────────────────────────────────────────────────────────

def ema(s: pd.Series, n: int) -> pd.Series:
    return s.ewm(span=n, adjust=False).mean()


def rsi(s: pd.Series, n: int) -> pd.Series:
    """RSI สูตร Wilder"""
    delta = s.diff()
    gain = delta.clip(lower=0)
    loss = -delta.clip(upper=0)
    avg_gain = gain.ewm(alpha=1 / n, adjust=False).mean()
    avg_loss = loss.ewm(alpha=1 / n, adjust=False).mean()
    rs = avg_gain / avg_loss.replace(0, pd.NA)
    return (100 - 100 / (1 + rs)).fillna(100)


def macd(s: pd.Series):
    line = ema(s, MACD_FAST) - ema(s, MACD_SLOW)
    signal = ema(line, MACD_SIGNAL)
    return line, signal, line - signal


def fmt(v, digits: int = 2) -> str:
    """จัดรูปตัวเลขให้อ่านง่าย เว้นว่างถ้ายังคำนวณไม่ได้"""
    try:
        if pd.isna(v):
            return "–"
    except (TypeError, ValueError):
        return "–"
    return f"{v:,.{digits}f}"


def label_axis(index: pd.DatetimeIndex, tf: str) -> list[str]:
    """ใช้ป้ายข้อความเป็นแกน X เพื่อไม่ให้เกิดช่องว่างวันหยุด/พักเที่ยง"""
    fmt = {"120m": "%d/%m %H:%M", "Day": "%d/%m/%y",
           "Week": "%d/%m/%y", "Month": "%m/%Y"}[tf]
    return [t.strftime(fmt) for t in index]


# ─────────────────────────────────────────────────────────────
# วาดกราฟ
# ─────────────────────────────────────────────────────────────

# ตำแหน่งแถวเริ่มต้นและคอลัมน์ของแต่ละช่อง (ราคา, RSI, MACD เรียงลงมา)
PANEL_POS = [(1, 1), (1, 2), (4, 1), (4, 2)]


def readout(fig, text: str, row: int, col: int, size: int = 9.5):
    """แถบตัวเลขมุมซ้ายบนของแต่ละช่อง"""
    fig.add_annotation(
        xref="x domain", yref="y domain", x=0.006, y=0.985,
        xanchor="left", yanchor="top", align="left",
        text=text, showarrow=False, font=dict(size=size),
        bgcolor="rgba(255,255,255,0.82)", borderpad=2,
        row=row, col=col,
    )


def value_tag(fig, value, color: str, row: int, col: int, digits: int = 2):
    """ป้ายค่าล่าสุดติดขอบขวาของช่อง"""
    if value is None or pd.isna(value):
        return
    fig.add_annotation(
        xref="x domain", yref="y", x=1.005, y=float(value),
        xanchor="left", yanchor="middle",
        text=f" {fmt(value, digits)} ", showarrow=False,
        font=dict(size=9.5, color="#FFFFFF"),
        bgcolor=color, borderpad=2.5,
        row=row, col=col,
    )


def draw_panel(fig, df: pd.DataFrame, tf: str, base_row: int, col: int, show_legend: bool):
    df = df.copy()
    for n in EMA_STYLE:
        df[f"EMA{n}"] = ema(df["Close"], n)
    df["RSI"] = rsi(df["Close"], RSI_PERIOD)
    df["MACD"], df["SIG"], df["HIST"] = macd(df["Close"])

    df = df.tail(BARS).round(4)
    x = label_axis(df.index, tf)

    fig.add_trace(go.Candlestick(
        x=x, open=df["Open"], high=df["High"], low=df["Low"], close=df["Close"],
        increasing_line_color=UP_COLOR, decreasing_line_color=DOWN_COLOR,
        increasing_fillcolor=UP_COLOR, decreasing_fillcolor=DOWN_COLOR,
        line_width=1, name="ราคา", legendgroup="price",
        showlegend=False, hoverinfo="x+y",
    ), row=base_row, col=col)

    for n, (color, width) in EMA_STYLE.items():
        fig.add_trace(go.Scatter(
            x=x, y=df[f"EMA{n}"], mode="lines", name=f"EMA{n}",
            line=dict(color=color, width=width),
            legendgroup=f"ema{n}", showlegend=show_legend, hoverinfo="skip",
        ), row=base_row, col=col)

    fig.add_trace(go.Bar(
        x=x, y=df["HIST"], name="MACD hist", marker_color="#D5D5D5",
        legendgroup="hist", showlegend=False, hoverinfo="skip",
    ), row=base_row + 1, col=col)
    fig.add_trace(go.Scatter(
        x=x, y=df["MACD"], mode="lines", name="MACD",
        line=dict(color=MACD_LINE_COLOR, width=1.3),
        legendgroup="macd", showlegend=show_legend,
    ), row=base_row + 1, col=col)
    fig.add_trace(go.Scatter(
        x=x, y=df["SIG"], mode="lines", name="Signal",
        line=dict(color=MACD_SIGNAL_COLOR, width=1.3),
        legendgroup="sig", showlegend=show_legend,
    ), row=base_row + 1, col=col)

    fig.add_trace(go.Scatter(
        x=x, y=df["RSI"], mode="lines", name=f"RSI{RSI_PERIOD}",
        line=dict(color=RSI_COLOR, width=1.3),
        legendgroup="rsi", showlegend=show_legend,
    ), row=base_row + 2, col=col)
    for lvl, lvl_color in RSI_LEVELS.items():
        fig.add_hline(y=lvl, line=dict(color=lvl_color, width=1, dash="dot"),
                      row=base_row + 2, col=col)

    # ── ตัวเลขล่าสุด ────────────────────────────────────────
    last = df.iloc[-1]
    prev_close = df["Close"].iloc[-2] if len(df) > 1 else last["Close"]
    bar_color = UP_COLOR if last["Close"] >= last["Open"] else DOWN_COLOR
    pct = (last["Close"] / prev_close - 1) * 100 if prev_close else 0.0

    ohlc = (f'<b>{tf}</b>   <span style="color:{bar_color}">'
            f'O {fmt(last["Open"])}   H {fmt(last["High"])}   '
            f'L {fmt(last["Low"])}   C {fmt(last["Close"])}   {pct:+.2f}%</span>')
    emas = "   ".join(
        f'<span style="color:{c}">E{n} {fmt(last[f"EMA{n}"])}</span>'
        for n, (c, _) in EMA_STYLE.items()
    )
    readout(fig, f"{ohlc}<br>{emas}", base_row, col)
    value_tag(fig, last["Close"], bar_color, base_row, col)

    readout(fig, f'<span style="color:{MACD_LINE_COLOR}"><b>MACD {fmt(last["MACD"], 3)}</b></span>'
                 f'   <span style="color:{MACD_SIGNAL_COLOR}"><b>SIG {fmt(last["SIG"], 3)}</b></span>',
            base_row + 1, col, size=9)

    readout(fig, f'<span style="color:{RSI_COLOR}"><b>RSI{RSI_PERIOD} '
                 f'{fmt(last["RSI"], 1)}</b></span>', base_row + 2, col, size=9)
    value_tag(fig, last["RSI"], RSI_COLOR, base_row + 2, col, digits=1)


def build_figure(ticker: str, panels: dict[str, pd.DataFrame],
                 height: int | None = CHART_HEIGHT) -> go.Figure:
    """height=None = ไม่ล็อกความสูง ปล่อยให้ยืดตามกล่องที่ครอบอยู่ (ใช้กับเว็บ)"""
    fig = make_subplots(
        rows=6, cols=2,
        row_heights=[0.21, 0.06, 0.07, 0.21, 0.06, 0.07],
        vertical_spacing=0.028, horizontal_spacing=0.075,
    )

    for i, tf in enumerate(TIMEFRAMES):
        df = panels.get(tf)
        if df is None or df.empty:
            continue
        base_row, col = PANEL_POS[i]
        draw_panel(fig, df, tf, base_row, col, show_legend=(i == 0))

    # ให้แกน X ของสามแถวในช่องเดียวกันเลื่อน/ซูมพร้อมกัน
    for base_row, col, anchor in ((1, 1, "x"), (1, 2, "x2"), (4, 1, "x7"), (4, 2, "x8")):
        for offset in (1, 2):
            fig.update_xaxes(matches=anchor, row=base_row + offset, col=col)
        for offset in (0, 1):
            fig.update_xaxes(showticklabels=False, row=base_row + offset, col=col)

    fig.update_xaxes(type="category", nticks=7, rangeslider_visible=False,
                     showgrid=True, gridcolor=GRID_COLOR,
                     tickangle=0, tickfont=dict(size=9))
    # แกนราคาอยู่ซ้าย เว้นขอบขวาไว้ให้ป้ายค่าล่าสุด
    fig.update_yaxes(showgrid=True, gridcolor=GRID_COLOR,
                     tickfont=dict(size=9), side="left")
    for base_row, col in PANEL_POS:
        fig.update_yaxes(range=[0, 100], dtick=25, row=base_row + 2, col=col)

    fig.update_layout(
        title=dict(text=f"{ticker}  ·  {datetime.now():%d/%m/%Y %H:%M}",
                   x=0.01, font=dict(size=16, color="#111")),
        height=height, autosize=True,
        paper_bgcolor=BG_COLOR, plot_bgcolor=BG_COLOR,
        font=dict(family="Arial, sans-serif", size=11, color="#333"),
        margin=dict(l=10, r=58, t=74, b=8),
        legend=dict(orientation="h", y=1.045, x=0.30, font=dict(size=10),
                    bgcolor="rgba(0,0,0,0)"),
        hovermode="x unified", dragmode="pan", bargap=0.1,
    )
    return fig


def save(fig: go.Figure, ticker: str, out_dir: str | None = None) -> str:
    out_dir = out_dir or OUTPUT_DIR
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{ticker.replace('.', '_')}.html")
    fig.write_html(
        path, include_plotlyjs="cdn", full_html=True,
        config={"scrollZoom": True, "displaylogo": False, "responsive": True},
    )
    return path


# ─────────────────────────────────────────────────────────────

def main():
    for ticker in TICKERS:
        print(f"กำลังดึงข้อมูล {ticker} ...")
        daily = fetch_daily(ticker)
        if daily.empty:
            print(f"  ไม่พบข้อมูลของ {ticker} — ตรวจชื่อย่อดูอีกที (ต้องมี .BK)")
            continue

        panels = {
            "120m": fetch_intraday(ticker),
            "Day": daily,
            "Week": to_period(daily, "W-FRI"),
            "Month": to_period(daily, "ME"),
        }
        if panels["120m"].empty:
            print("  ไม่มีข้อมูล intraday ของตัวนี้ — ช่อง 120 นาทีจะว่าง")

        print("  เซฟไว้ที่:", save(build_figure(ticker, panels), ticker))


if __name__ == "__main__":
    main()
