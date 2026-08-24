//+------------------------------------------------------------------+
//|  MySignal_DE.mq4                                                 |
//|  DE (Deviation Expert) — เงินทุนไหลเข้า/ออก · หน้าต่างล่าง         |
//|                                                                  |
//|  ผลต่างของราคาถ่วงน้ำหนักด้วยวอลุ่ม เร็ว(13) - ช้า(55) แล้วปรับให้ลื่น|
//|   แท่งเขียว = ค่ากำลังขึ้น (เงินไหลเข้า)                            |
//|   แท่งแดง  = ค่ากำลังลง  (เงินไหลออก)                              |
//|   เหนือเส้น 0 = ฝั่งซื้อคุมเกม · ใต้เส้น 0 = ฝั่งขายคุมเกม           |
//|                                                                  |
//|  ⚠ MT4 ให้แค่ tick volume (จำนวนครั้งที่ราคาขยับ) ไม่ใช่ปริมาณจริง   |
//|    ค่าที่ได้จึงเป็นแนวโน้ม ไม่ใช่ตัวเลขเดียวกับบนเว็บ                 |
//|                                                                  |
//|  วางที่ MQL4 > Indicators แล้วกด F7 คอมไพล์                        |
//|  เป็นเครื่องมือช่วยดูกราฟ ไม่ใช่คำแนะนำการลงทุน                     |
//+------------------------------------------------------------------+
#property copyright "Mathold"
#property version   "1.00"
#property strict
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_color1 clrLime
#property indicator_color2 clrRed
#property indicator_color3 clrWhite
#property indicator_level1 0.0
#property indicator_levelcolor clrGold
#property indicator_levelstyle STYLE_DOT

input int   DeFast     = 13;        // VWMA เร็ว
input int   DeSlow     = 55;        // VWMA ช้า
input int   DeSmooth   = 5;         // EMA ปรับให้ลื่น
input color InColor    = clrLime;   // เขียว = เงินไหลเข้า
input color OutColor   = clrRed;    // แดง   = เงินไหลออก
input int   HistWidth  = 2;         // ความหนาแท่ง
input bool  ShowLine   = true;      // ลากเส้นทับแท่งด้วย

double UpBuf[], DnBuf[], LineBuf[];

double g_a;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(DeFast < 1 || DeSlow < 1 || DeFast >= DeSlow || DeSmooth < 1)
     {
      Print("MySignal_DE: ค่าไม่ถูกต้อง — ต้องเป็นบวกและ DeFast < DeSlow");
      return(INIT_PARAMETERS_INCORRECT);
     }

   IndicatorShortName(StringFormat("DE %d/%d", DeFast, DeSlow));
   IndicatorDigits(Digits + 1);

   SetIndexBuffer(0, UpBuf);
   SetIndexBuffer(1, DnBuf);
   SetIndexBuffer(2, LineBuf);

   SetIndexStyle(0, DRAW_HISTOGRAM, STYLE_SOLID, HistWidth, InColor);
   SetIndexStyle(1, DRAW_HISTOGRAM, STYLE_SOLID, HistWidth, OutColor);
   SetIndexStyle(2, (ShowLine ? DRAW_LINE : DRAW_NONE), STYLE_SOLID, 1, clrWhite);

   SetIndexLabel(0, "DE เงินไหลเข้า");
   SetIndexLabel(1, "DE เงินไหลออก");
   SetIndexLabel(2, "DE");

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);

   g_a = 2.0 / (DeSmooth + 1.0);
   return(INIT_SUCCEEDED);
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
   if(rates_total < DeSlow + 10)
      return(0);

   int start;
   if(prev_calculated <= 0)
     {
      start = rates_total - 1 - DeSlow;
      if(start < 2)
         return(0);
      for(int j = rates_total - 1; j > start; j--)
        {
         UpBuf[j] = EMPTY_VALUE;
         DnBuf[j] = EMPTY_VALUE;
         LineBuf[j] = 0;
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
      double raw = Vwma(i, DeFast, close, tick_volume, rates_total)
                 - Vwma(i, DeSlow, close, tick_volume, rates_total);
      LineBuf[i] = g_a * raw + (1 - g_a) * LineBuf[i+1];

      UpBuf[i] = EMPTY_VALUE;
      DnBuf[i] = EMPTY_VALUE;
      if(LineBuf[i] >= LineBuf[i+1])
         UpBuf[i] = LineBuf[i];
      else
         DnBuf[i] = LineBuf[i];
     }

   return(rates_total);
  }

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
