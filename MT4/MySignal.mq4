//+------------------------------------------------------------------+
//|  MySignal.mq4                                                    |
//|  ยกชุด My Signal จากเว็บ (my_signal.py) มาลงกราฟ MT4              |
//|                                                                  |
//|   · ริบบิ้น BBE  = double-EMA 13/34   เขียว = ขาขึ้น · แดง = ขาลง   |
//|   · ลูกศรสัญญาณ (Signal Aditor)                                   |
//|       เหลือง ▲ = ซื้อ · แดง ▼ = ขาย                               |
//|       จุดเขียว = ถือของต่อ · จุดชมพู = ถือเงินสด                    |
//|   · เลข 1-9 Pattern 49  ฟ้า = นับขึ้น (บนแท่ง) · ส้ม = นับลง (ใต้แท่ง)|
//|   · กล่องสถานะมุมจอ  ซื้อเต็มไม้ / ครึ่งไม้ / ถือต่อ / ลดไม้ / ออก    |
//|   · แจ้งเตือนตอนเกิดสัญญาณ (ป๊อปอัป / เข้าแอปมือถือ / อีเมล)         |
//|                                                                  |
//|  DE คำนวณอยู่ในไฟล์นี้ด้วย (ใช้ตัดสินสัญญาณ) แต่ถ้าอยากเห็นเป็นแท่ง  |
//|  ให้ลง MySignal_DE.mq4 เพิ่มในหน้าต่างล่าง                          |
//|                                                                  |
//|  ⚠ วอลุ่มใน MT4 เป็น "tick volume" (จำนวนครั้งที่ราคาขยับ)          |
//|    ไม่ใช่ปริมาณซื้อขายจริงแบบหุ้น ค่า DE/MCD จึงไม่ตรงกับบนเว็บ       |
//|                                                                  |
//|  วิธีติดตั้ง: File > Open Data Folder > MQL4 > Indicators         |
//|              วางไฟล์ > MetaEditor กด F7 > Navigator > Refresh    |
//|                                                                  |
//|  เป็นเครื่องมือช่วยดูกราฟ ไม่ใช่คำแนะนำการลงทุน                     |
//+------------------------------------------------------------------+
#property copyright "Mathold"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 8

#property indicator_color1 clrLimeGreen
#property indicator_color2 clrLimeGreen
#property indicator_color3 clrCrimson
#property indicator_color4 clrCrimson
#property indicator_color5 clrYellow
#property indicator_color6 clrRed
#property indicator_color7 clrSpringGreen
#property indicator_color8 clrHotPink

//====================== อินพุต =====================================
// ⚠ คำอธิบายอินพุตต้องเป็นภาษาอังกฤษเท่านั้น
//   MT4 บน Mac (Wine) วาดหน้าต่าง Inputs เป็น ANSI ภาษาไทยจะกลายเป็น ????
//   คำแปลไทยอยู่ในคอมเมนต์เหนือแต่ละกลุ่มข้างล่างนี้แทน

// ── ริบบิ้น BBE ── EMA ซ้อนสองชั้น เร็ว/ช้า · สีขาขึ้น/ขาลง · ความหนาแท่ง
input string __s1__          = "--- BBE ribbon ---";
input int    BbeFast         = 13;            // Fast EMA (double smoothed)
input int    BbeSlow         = 34;            // Slow EMA (double smoothed)
input color  RibbonUpColor   = clrLimeGreen;  // Ribbon color when bullish
input color  RibbonDnColor   = clrCrimson;    // Ribbon color when bearish
input int    RibbonWidth     = 1;             // Ribbon thickness (1-3)

// ── DE ── ผลต่าง VWMA เร็ว-ช้า แล้วปรับให้ลื่น (ใช้ตัดสินสัญญาณ)
input string __s2__          = "--- DE (drives the signal) ---";
input int    DeFast          = 13;            // Fast VWMA
input int    DeSlow          = 55;            // Slow VWMA
input int    DeSmooth        = 5;             // Smoothing EMA

// ── ลูกศร / จุดสถานะแท่ง ── เหลือง=ซื้อ แดง=ขาย เขียว=ถือของ ชมพู=ถือเงินสด
input string __s3__          = "--- Signal arrows / state dots ---";
input bool   ShowSignalArrow = true;          // Show buy / sell arrows
input bool   ShowStateDots   = true;          // Show hold / cash dots
input color  BuyColor        = clrYellow;     // Buy signal (yellow)
input color  SellColor       = clrRed;        // Sell signal (red)
input color  HoldColor       = clrSpringGreen;// Hold position (green)
input color  CashColor       = clrHotPink;    // Stay in cash (pink)
input double MarkGapAtr      = 0.7;           // Arrow gap from bar (x ATR14)

// ── Pattern 49 ── เลข 1-9 · ฟ้า = นับขึ้น (เหนือแท่ง) · ส้ม = นับลง (ใต้แท่ง)
input string __s4__          = "--- Pattern 49 count (1-9) ---";
input bool   ShowCount       = true;          // Show the 1-9 count
input int    CountFontSize   = 8;             // Count font size
input color  CountUpColor    = clrAqua;       // Up count (above bar)
input color  CountDnColor    = clrOrange;     // Down count (below bar)
input int    LabelBars       = 400;           // Draw labels over last N bars

// ── กล่องสถานะ ── สรุปว่าตอนนี้ควรทำอะไร
//    StatusCorner : 0 = ซ้ายบน · 1 = ขวาบน · 2 = ซ้ายล่าง · 3 = ขวาล่าง
//    StatusY = 34 ให้กล่องต่ำกว่าบรรทัดชื่อสินค้า/ราคาที่ MT4 เขียนไว้มุมซ้ายบน
//    StatusEnglish = true ใช้ตัวอังกฤษ (BUY FULL / HOLD / REDUCE / EXIT / WAIT)
input string __s5__          = "--- Status box ---";
input bool   ShowStatusBox   = true;          // Show the status box
input bool   StatusOnClosedBar = true;        // Read the closed bar (recommended)
input int    StatusCorner    = 0;             // Corner: 0=TL 1=TR 2=BL 3=BR
input int    StatusX         = 6;             // Offset from corner - X (px)
input int    StatusY         = 34;            // Offset from corner - Y (px)
input int    StatusFontSize  = 10;            // Status font size
input bool   StatusEnglish   = true;          // English text (Wine shows Thai as ??)

// ── แจ้งเตือน ── ป๊อปอัปในโปรแกรม / เข้าแอปมือถือ / อีเมล
input string __s6__          = "--- Alerts ---";
input bool   AlertOnSignal   = true;          // Alert on buy / sell signal
input bool   AlertPopup      = true;          // Popup + sound in MT4
input bool   AlertPush       = false;         // Push to MT4 mobile (set MetaQuotes ID)
input bool   AlertEmail      = false;         // Email (set Tools > Options > Email)

//====================== บัฟเฟอร์ ===================================
double UpFast[], UpSlow[], DnFast[], DnSlow[];      // 0-3 ริบบิ้น
double BuyMark[], SellMark[], HoldDot[], CashDot[]; // 4-7 ลูกศร/จุด
double E1F[], RibF[], E1S[], RibS[];                // 8-11 คำนวณริบบิ้น
double DeBuf[], P49U[], P49D[], SigBuf[];           // 12-15 DE / นับ / รหัสสัญญาณ

//--- รหัสสัญญาณใน SigBuf
#define SIG_BUY   1
#define SIG_SELL  2
#define SIG_HOLD  3
#define SIG_CASH  4

#define P49_LOOKBACK 4
#define P49_TARGET   9

const string OBJ_PREFIX = "MySig_";

datetime g_lastBar      = 0;   // แท่งล่าสุดที่วาดป้ายไปแล้ว
datetime g_lastAlertBar = 0;   // แท่งล่าสุดที่เตือนไปแล้ว

double g_aF, g_aS, g_aD;       // ค่าคงที่ EMA

//+------------------------------------------------------------------+
int OnInit()
  {
   if(BbeFast < 1 || BbeSlow < 1 || BbeFast >= BbeSlow)
     {
      Print("MySignal: bad EMA inputs - must be positive and BbeFast < BbeSlow");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(DeFast < 1 || DeSlow < 1 || DeFast >= DeSlow || DeSmooth < 1)
     {
      Print("MySignal: bad DE inputs - must be positive and DeFast < DeSlow");
      return(INIT_PARAMETERS_INCORRECT);
     }

   IndicatorShortName(StringFormat("My Signal %d/%d", BbeFast, BbeSlow));
   IndicatorDigits(Digits);
   IndicatorBuffers(16);

   SetIndexBuffer(0, UpFast);   SetIndexBuffer(1, UpSlow);
   SetIndexBuffer(2, DnFast);   SetIndexBuffer(3, DnSlow);
   SetIndexBuffer(4, BuyMark);  SetIndexBuffer(5, SellMark);
   SetIndexBuffer(6, HoldDot);  SetIndexBuffer(7, CashDot);
   SetIndexBuffer(8, E1F);      SetIndexBuffer(9, RibF);
   SetIndexBuffer(10, E1S);     SetIndexBuffer(11, RibS);
   SetIndexBuffer(12, DeBuf);   SetIndexBuffer(13, P49U);
   SetIndexBuffer(14, P49D);    SetIndexBuffer(15, SigBuf);

   // ริบบิ้น = ฮิสโตแกรมคู่ MT4 จะระบายสีระหว่างสองเส้นให้เอง
   SetIndexStyle(0, DRAW_HISTOGRAM, STYLE_SOLID, RibbonWidth, RibbonUpColor);
   SetIndexStyle(1, DRAW_HISTOGRAM, STYLE_SOLID, RibbonWidth, RibbonUpColor);
   SetIndexStyle(2, DRAW_HISTOGRAM, STYLE_SOLID, RibbonWidth, RibbonDnColor);
   SetIndexStyle(3, DRAW_HISTOGRAM, STYLE_SOLID, RibbonWidth, RibbonDnColor);

   SetIndexStyle(4, DRAW_ARROW, STYLE_SOLID, 2, BuyColor);   SetIndexArrow(4, 233);
   SetIndexStyle(5, DRAW_ARROW, STYLE_SOLID, 2, SellColor);  SetIndexArrow(5, 234);
   SetIndexStyle(6, DRAW_ARROW, STYLE_SOLID, 1, HoldColor);  SetIndexArrow(6, 159);
   SetIndexStyle(7, DRAW_ARROW, STYLE_SOLID, 1, CashColor);  SetIndexArrow(7, 159);

   for(int b = 8; b < 16; b++)
      SetIndexStyle(b, DRAW_NONE);

   SetIndexLabel(0, "BBE fast (up)");
   SetIndexLabel(1, "BBE slow (up)");
   SetIndexLabel(2, "BBE fast (down)");
   SetIndexLabel(3, "BBE slow (down)");
   SetIndexLabel(4, "Buy signal");
   SetIndexLabel(5, "Sell signal");
   SetIndexLabel(6, "Hold");
   SetIndexLabel(7, "Cash");
   for(int k = 8; k < 16; k++)
      SetIndexLabel(k, NULL);

   for(int e = 0; e < 8; e++)
      SetIndexEmptyValue(e, EMPTY_VALUE);

   g_aF = 2.0 / (BbeFast + 1.0);
   g_aS = 2.0 / (BbeSlow + 1.0);
   g_aD = 2.0 / (DeSmooth + 1.0);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ClearObjects();
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   int need = DeSlow + P49_LOOKBACK + 5;
   if(rates_total < need + 10)
      return(0);

   int start;

   if(prev_calculated <= 0)
     {
      start = rates_total - 1 - DeSlow;   // ต้องมีแท่งย้อนหลังพอสำหรับ VWMA ช้า
      if(start < 2)
         return(0);

      // แท่งที่เก่ากว่าจุดเริ่ม = ปล่อยว่าง แล้ววางค่าตั้งต้นให้สูตรวนซ้ำ
      for(int j = rates_total - 1; j > start; j--)
        {
         UpFast[j] = EMPTY_VALUE;  UpSlow[j] = EMPTY_VALUE;
         DnFast[j] = EMPTY_VALUE;  DnSlow[j] = EMPTY_VALUE;
         BuyMark[j] = EMPTY_VALUE; SellMark[j] = EMPTY_VALUE;
         HoldDot[j] = EMPTY_VALUE; CashDot[j] = EMPTY_VALUE;
         E1F[j] = close[j];  RibF[j] = close[j];
         E1S[j] = close[j];  RibS[j] = close[j];
         DeBuf[j] = 0;  P49U[j] = 0;  P49D[j] = 0;  SigBuf[j] = SIG_CASH;
        }
     }
   else
     {
      start = rates_total - prev_calculated;
      if(start < 1)
         start = 1;
      if(start > rates_total - 2 - DeSlow)
         start = rates_total - 2 - DeSlow;
      if(start < 0)
         return(rates_total);
     }

   for(int i = start; i >= 0; i--)
     {
      double c = close[i];

      // ── ริบบิ้น: EMA ซ้อนสองชั้น (ตรงกับ _dema() บนเว็บ) ──
      E1F[i]  = g_aF * c       + (1 - g_aF) * E1F[i+1];
      RibF[i] = g_aF * E1F[i]  + (1 - g_aF) * RibF[i+1];
      E1S[i]  = g_aS * c       + (1 - g_aS) * E1S[i+1];
      RibS[i] = g_aS * E1S[i]  + (1 - g_aS) * RibS[i+1];

      // ── DE: ผลต่างราคาถ่วงน้ำหนักด้วยวอลุ่ม เร็ว-ช้า แล้วปรับให้ลื่น ──
      double raw = Vwma(i, DeFast, close, tick_volume, rates_total)
                 - Vwma(i, DeSlow, close, tick_volume, rates_total);
      DeBuf[i] = g_aD * raw + (1 - g_aD) * DeBuf[i+1];

      // ── นับ Pattern 49 เทียบกับปิดของ 4 แท่งก่อน ──
      P49U[i] = 0;
      P49D[i] = 0;
      if(i + P49_LOOKBACK < rates_total)
        {
         if(c > close[i + P49_LOOKBACK])
            P49U[i] = (P49U[i+1] >= P49_TARGET ? 1 : P49U[i+1] + 1);
         if(c < close[i + P49_LOOKBACK])
            P49D[i] = (P49D[i+1] >= P49_TARGET ? 1 : P49D[i+1] + 1);
        }

      // ── ริบบิ้นสีอะไร ──
      bool bull  = (RibF[i]   >= RibS[i]);
      bool bull1 = (RibF[i+1] >= RibS[i+1]);

      UpFast[i] = EMPTY_VALUE;  UpSlow[i] = EMPTY_VALUE;
      DnFast[i] = EMPTY_VALUE;  DnSlow[i] = EMPTY_VALUE;
      if(bull) { UpFast[i] = RibF[i]; UpSlow[i] = RibS[i]; }
      else     { DnFast[i] = RibF[i]; DnSlow[i] = RibS[i]; }

      // ── สีแท่ง/สัญญาณ (ลำดับการทับต้องเหมือน signal_colors() บนเว็บ) ──
      bool crossUp = (DeBuf[i] > 0 && DeBuf[i+1] <= 0);
      bool crossDn = (DeBuf[i] < 0 && DeBuf[i+1] >= 0);

      int code = (bull ? SIG_HOLD : SIG_CASH);
      if(bull && crossUp)  code = SIG_BUY;
      if(bull && crossDn)  code = SIG_SELL;
      if(bull && !bull1)   code = SIG_BUY;    // ริบบิ้นพลิกเขียว = ซื้อเสมอ
      if(!bull && bull1)   code = SIG_SELL;   // ริบบิ้นพลิกแดง  = ขายเสมอ
      SigBuf[i] = code;

      double atr = iATR(NULL, 0, 14, i);
      if(atr <= 0)
         atr = (high[i] - low[i]);
      double gap = atr * MarkGapAtr;

      BuyMark[i]  = EMPTY_VALUE;  SellMark[i] = EMPTY_VALUE;
      HoldDot[i]  = EMPTY_VALUE;  CashDot[i]  = EMPTY_VALUE;

      if(ShowSignalArrow && code == SIG_BUY)
         BuyMark[i] = low[i] - gap;
      else if(ShowSignalArrow && code == SIG_SELL)
         SellMark[i] = high[i] + gap;
      else if(ShowStateDots && code == SIG_HOLD)
         HoldDot[i] = low[i] - gap * 0.45;
      else if(ShowStateDots && code == SIG_CASH)
         CashDot[i] = low[i] - gap * 0.45;
     }

   // วาดเลข/กล่องสถานะเฉพาะตอนเปิดกราฟใหม่หรือมีแท่งใหม่ (ไม่ต้องทำทุก tick)
   if(prev_calculated <= 0 || g_lastBar != time[0])
     {
      g_lastBar = time[0];
      if(ShowCount)
         DrawCounts(time, high, low, rates_total);
      if(ShowStatusBox)
         DrawStatus(close, rates_total);
     }

   if(AlertOnSignal && prev_calculated > 0)
      CheckAlert(time, close, rates_total);

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| ราคาเฉลี่ยถ่วงน้ำหนักด้วยวอลุ่ม n แท่งนับจากแท่ง i                   |
//| วอลุ่มรวมเป็นศูนย์ (ตลาดปิดยาว) ให้ถอยไปใช้ค่าเฉลี่ยธรรมดา           |
//+------------------------------------------------------------------+
double Vwma(const int i, const int n, const double &close[],
            const long &vol[], const int rates_total)
  {
   double num = 0, den = 0, sum = 0;
   int cnt = 0;

   for(int k = i; k < i + n && k < rates_total; k++)
     {
      double v = (double)vol[k];
      num += close[k] * v;
      den += v;
      sum += close[k];
      cnt++;
     }

   if(cnt == 0)
      return(0);
   if(den <= 0)
      return(sum / cnt);
   return(num / den);
  }

//+------------------------------------------------------------------+
//| เลข 1-9 Pattern 49                                                |
//| โชว์เฉพาะรอบที่นับครบ 9 กับรอบที่ยังนับค้างอยู่ที่แท่งล่าสุด         |
//| (ถ้าโชว์ทุกรอบ ตัวเลขจะเต็มกราฟจนอ่านไม่ออก)                        |
//+------------------------------------------------------------------+
void DrawCounts(const datetime &time[], const double &high[],
                const double &low[], const int rates_total)
  {
   DeleteByPrefix(OBJ_PREFIX + "N");

   int win = LabelBars;
   if(win > rates_total - 2)
      win = rates_total - 2;
   if(win < 2)
      return;

   for(int side = 0; side < 2; side++)
     {
      int i = win;
      while(i >= 0)
        {
         double v0 = (side == 0 ? P49U[i] : P49D[i]);
         if(v0 <= 0)
           {
            i--;
            continue;
           }

         // ไล่หาปลายรอบ (เดินไปทางแท่งใหม่กว่า = ดัชนีลดลง)
         int k = i;
         double mx = 0;
         while(k >= 0)
           {
            double v = (side == 0 ? P49U[k] : P49D[k]);
            if(v <= 0)
               break;
            if(k != i && v == 1)      // เริ่มรอบใหม่ = รอบเดิมจบแล้ว
               break;
            if(v > mx)
               mx = v;
            k--;
           }

         if(mx >= P49_TARGET || k < 0)   // ครบ 9 หรือเป็นรอบที่ยังค้างอยู่
           {
            for(int m = i; m > k; m--)
              {
               double v = (side == 0 ? P49U[m] : P49D[m]);
               if(v <= 0)
                  continue;
               double atr = iATR(NULL, 0, 14, m);
               if(atr <= 0)
                  atr = high[m] - low[m];
               // เลข 1 (เริ่มรอบ = จุดซื้อตามคู่มือ) กับเลข 9 (จบรอบ) ทำตัวใหญ่กว่าเพื่อน
               bool big  = ((int)v == 1 || (int)v >= P49_TARGET);
               double pad = atr * (big ? 0.45 : 0.35);
               double price = (side == 0 ? high[m] + pad : low[m] - pad);
               DrawText(OBJ_PREFIX + "N" + (string)side + (string)(long)time[m],
                        time[m], price, DoubleToString(v, 0),
                        (side == 0 ? CountUpColor : CountDnColor),
                        (big ? CountFontSize + 4 : CountFontSize),
                        (side == 0 ? ANCHOR_LOWER : ANCHOR_UPPER),
                        (big ? "Arial Black" : "Tahoma"));
              }
           }

         i = k;
        }
     }
  }

//+------------------------------------------------------------------+
//| กล่องสถานะ — สรุปว่าตอนนี้ควรทำอะไร (ตรรกะเดียวกับ status() บนเว็บ) |
//+------------------------------------------------------------------+
void DrawStatus(const double &close[], const int rates_total)
  {
   int sh = (StatusOnClosedBar ? 1 : 0);
   if(rates_total < sh + 10)
      return;

   string label = T("อยู่เฉย", "WAIT"), why = T("ริบบิ้นแดง", "ribbon red");
   color  bg = CashColor, fg = clrBlack;

   bool   bull = (RibF[sh] >= RibS[sh]);
   int    code = (int)SigBuf[sh];
   double de   = DeBuf[sh];
   bool   deUp = (DeBuf[sh] >= DeBuf[sh+1]);

   if(code == SIG_SELL)
     {
      label = T("ออก", "EXIT");
      why   = T("Sell signal", "sell signal");
      bg = SellColor;  fg = clrWhite;
     }
   else if(!bull)
     {
      label = T("อยู่เฉย", "WAIT");
      why   = T("ริบบิ้นแดง", "ribbon red");
      bg = CashColor;  fg = clrBlack;
     }
   else if(code == SIG_BUY)
     {
      if(de > 0 && deUp)
        {
         label = T("ซื้อเต็มไม้", "BUY FULL");
         why   = T("ริบบิ้นเขียว + DE เหนือ 0 และกำลังขึ้น", "BBE green + DE above 0 rising");
         bg = HoldColor;  fg = clrBlack;
        }
      else
        {
         label = T("ซื้อครึ่งไม้", "BUY HALF");
         why   = (de <= 0 ? T("DE ยังใต้ 0", "DE still below 0")
                          : T("DE ยังไม่เขียว", "DE not rising yet"));
         bg = BuyColor;  fg = clrBlack;
        }
     }
   else
     {
      // ถือของอยู่ — เช็กว่าแรงเริ่มหมดหรือยัง (เกณฑ์เดียวกับบนเว็บ)
      bool deFading = (de > 0
                       && DeBuf[sh]   < DeBuf[sh+1]
                       && DeBuf[sh+1] < DeBuf[sh+2]
                       && DeBuf[sh+2] < DeBuf[sh+3]);
      bool counted  = (P49U[sh] >= P49_TARGET);
      double w0 = MathAbs(RibF[sh]   - RibS[sh]);
      double w5 = MathAbs(RibF[sh+5] - RibS[sh+5]);
      bool narrowing = (w5 > 0 && w0 < w5 * 0.85);

      if(deFading || counted || narrowing)
        {
         label = T("ลดไม้", "REDUCE");
         why   = (deFading ? T("DE ถอยลงหาเส้น 0", "DE fading toward 0")
                           : (counted ? T("นับขึ้นครบ 9 แล้ว", "count reached 9")
                                      : T("ริบบิ้นเริ่มบีบ", "ribbon narrowing")));
         bg = clrOrange;  fg = clrBlack;
        }
      else
        {
         label = T("ถือต่อ", "HOLD");
         why   = T("ยังไม่มีอะไรเปลี่ยน", "nothing changed");
         bg = clrSeaGreen;  fg = clrWhite;
        }
     }

   string text = StringFormat("%s  |  %s %s", label, Symbol(), TFText(Period()));

   // กว้างตามข้อความจริง ไม่งั้นตัวอักษรล้นกล่อง
   int len = (int)MathMax(StringLen(text), StringLen(why) + 2);
   int w   = 20 + (int)(len * StatusFontSize * 0.62);
   int h   = StatusFontSize * 2 + 22;

   // MT4 วัดระยะไปที่มุมซ้ายบนของวัตถุเสมอ ต่อให้ผูกไว้มุมขวา/ล่าง
   // ถ้าไม่บวกความกว้าง/สูงกลับเข้าไป กล่องจะยื่นออกนอกจอจนเห็นแค่แถบบาง ๆ
   bool rightC  = (StatusCorner == 1 || StatusCorner == 3);
   bool bottomC = (StatusCorner == 2 || StatusCorner == 3);
   int  bx = (rightC  ? StatusX + w : StatusX);
   int  by = (bottomC ? StatusY + h : StatusY);

   int t1x = (rightC  ? bx - 8 : bx + 8);
   int t1y = (bottomC ? by - 4 : by + 4);
   int t2y = (bottomC ? by - (StatusFontSize + 9) : by + StatusFontSize + 9);

   string rect = OBJ_PREFIX + "BOX";
   if(ObjectFind(0, rect) < 0)
      ObjectCreate(0, rect, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, rect, OBJPROP_CORNER, StatusCorner);
   ObjectSetInteger(0, rect, OBJPROP_XDISTANCE, bx);
   ObjectSetInteger(0, rect, OBJPROP_YDISTANCE, by);
   ObjectSetInteger(0, rect, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, rect, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, rect, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, rect, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, rect, OBJPROP_COLOR, bg);
   ObjectSetInteger(0, rect, OBJPROP_BACK, false);
   ObjectSetInteger(0, rect, OBJPROP_SELECTABLE, false);

   DrawLabel(OBJ_PREFIX + "TXT1", text, fg, StatusFontSize,      t1x, t1y);
   DrawLabel(OBJ_PREFIX + "TXT2", why,  fg, StatusFontSize - 2,  t1x, t2y);
  }

//+------------------------------------------------------------------+
//| เลือกภาษาข้อความ — ไทยอ่านง่ายกว่า แต่ MT4 บน Mac/Wine วาดไม่ได้    |
//+------------------------------------------------------------------+
string T(const string th, const string en)
  {
   return(StatusEnglish ? en : th);
  }

//+------------------------------------------------------------------+
void DrawLabel(const string name, const string text, const color clr,
               const int size, const int x, const int y)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, StatusCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Tahoma");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
void DrawText(const string name, const datetime t, const double price,
              const string text, const color clr, const int size,
              const int anchor, const string font = "Tahoma")
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

//+------------------------------------------------------------------+
//| เตือนครั้งเดียวต่อแท่ง                                             |
//+------------------------------------------------------------------+
void CheckAlert(const datetime &time[], const double &close[],
                const int rates_total)
  {
   int sh = (StatusOnClosedBar ? 1 : 0);
   if(rates_total < sh + 5)
      return;

   int code = (int)SigBuf[sh];
   if(code != SIG_BUY && code != SIG_SELL)
      return;
   if(g_lastAlertBar == time[sh])
      return;
   g_lastAlertBar = time[sh];

   string side = (code == SIG_BUY ? T("ซื้อ (Buy)", "BUY") : T("ขาย (Sell)", "SELL"));
   string msg  = StringFormat("My Signal | %s %s | %s | %s %s",
                              Symbol(), TFText(Period()), side,
                              T("ราคา", "price"),
                              DoubleToString(close[sh], Digits));

   if(AlertPopup) Alert(msg);
   if(AlertPush)  SendNotification(msg);
   if(AlertEmail) SendMail("My Signal " + Symbol(), msg);
   Print(msg);
  }

//+------------------------------------------------------------------+
string TFText(const int tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN");
     }
   return("TF" + (string)tf);
  }

//+------------------------------------------------------------------+
void DeleteByPrefix(const string prefix)
  {
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, prefix, 0) == 0)
         ObjectDelete(0, name);
     }
  }

//+------------------------------------------------------------------+
void ClearObjects()
  {
   DeleteByPrefix(OBJ_PREFIX);
  }
//+------------------------------------------------------------------+
