//+------------------------------------------------------------------+
//|  MySignal_EA.mq4                                                 |
//|  EA เทรดตามกฎ My Signal (ชุดเดียวกับ MySignal.mq4)                |
//|                                                                  |
//|  เข้าไม้  : แท่งสัญญาณ "ซื้อ" = ริบบิ้น BBE พลิกเขียว                |
//|             หรือ DE ตัดขึ้นเหนือ 0 ขณะริบบิ้นเขียวอยู่แล้ว            |
//|  ออกไม้  : แท่งสัญญาณ "ขาย" = ริบบิ้นพลิกแดง หรือ DE ตัดลงใต้ 0     |
//|  ครึ่งไม้ : สัญญาณซื้อมาแต่ DE ยังไม่ยืนยัน → เข้าครึ่งขนาด           |
//|  ลดไม้   : ถือแล้วแรงเริ่มหมด (DE ถอย / นับครบ 9 / ริบบิ้นบีบ)       |
//|             → ปิดครึ่งไม้ครั้งเดียวต่อออเดอร์                        |
//|                                                                  |
//|  ตัวกรองทุกตัวปิดไว้เป็นค่าเริ่มต้น = ได้กฎ My Signal ล้วน ๆ          |
//|  เปิดทีละตัวแล้ว backtest เทียบ จะเห็นว่าตัวไหนช่วยจริง               |
//|                                                                  |
//|  วิธีติดตั้ง: File > Open Data Folder > MQL4 > Experts             |
//|              วางไฟล์ > MetaEditor F7 > ลากใส่กราฟ + ติ๊ก AutoTrading|
//|                                                                  |
//|  *** ต้อง backtest และรันบัญชีเดโมให้ผ่านก่อนใช้เงินจริงเสมอ        |
//|      ผลในอดีตไม่รับประกันอนาคต · ไฟล์นี้ไม่ใช่คำแนะนำการลงทุน ***    |
//+------------------------------------------------------------------+
#property copyright "Mathold"
#property version   "1.00"
#property strict

//====================== อินพุต =====================================
input string  __s1__            = "--- My Signal rules ---";
input int     BbeFast           = 13;   // Fast EMA (double smoothed)
input int     BbeSlow           = 34;   // Slow EMA (double smoothed)
input int     DeFast            = 13;   // Fast VWMA
input int     DeSlow            = 55;   // Slow VWMA
input int     DeSmooth          = 5;   // DE smoothing EMA
input int     CalcBars          = 400;   // Bars to calculate per pass
input bool    TradeOnBarClose   = true;   // Trade on closed bar only (recommended)
input bool    AllowShort        = false;   // Allow short trades (default: long only)
input bool    CloseOnOpposite   = true;   // Opposite signal closes the trade

input string  __s2__            = "--- My Signal filters ---";
input bool    RequireDeAbove0   = false;   // Buy only when DE is above 0
input bool    HalfLotUnconfirmed= true;   // Half lot when DE not confirmed
input bool    SkipWhenCount9    = false;   // Skip entry when up-count reached 9
input bool    ReduceOnFade      = false;   // Close half when status = REDUCE
input bool    UseMcdFilter      = false;   // Use MCD confirm (needs MySignal_MCD.ex4)

input string  __s3__            = "--- General filters (all off = pure rules) ---";
input bool    UseTrendFilter    = false;   // Big trend: buy only above long EMA
input int     TrendEMA          = 200;   // Long EMA period
input bool    UseAdxFilter      = false;   // ADX must exceed the minimum
input int     AdxPeriod         = 14;   // ADX period
input double  AdxMin            = 22.0;   // ADX minimum
input bool    UseRibbonGapFilter= false;   // Ribbon must be wide enough (skip flat)
input double  GapAtrMultiple    = 0.25;   // Gap >= n x ATR

input string  __s4__            = "--- Stop loss / take profit ---";
input bool    UseAtrStops       = true;   // true = ATR based, false = fixed pips
input int     AtrPeriod         = 14;   // ATR period
input double  SlAtrMultiple     = 2.0;   // SL = n x ATR
input double  TpAtrMultiple     = 0;   // TP = n x ATR (0 = no TP)
input double  SlPips            = 300;   // SL in pips (when UseAtrStops = false)
input double  TpPips            = 0;   // TP in pips (0 = no TP)
input bool    UseBreakEven      = false;   // Move SL to entry at target profit
input double  BreakEvenAtR      = 1.0;   // Profit in R before break-even
input bool    UseTrailing       = false;   // ATR trailing stop
input double  TrailAtrMultiple  = 2.0;   // Trail = n x ATR

input string  __s5__            = "--- Position size / risk ---";
input bool    UseRiskPercent    = true;   // true = size from % of balance
input double  RiskPercent       = 1.0;   // Risk per trade (% of balance)
input double  FixedLots         = 0.01;   // Fixed lots (when UseRiskPercent = false)
input double  MaxLots           = 5.0;   // Lot ceiling (safety)

input string  __s6__            = "--- Context filters ---";
input double  MaxSpreadPips     = 5.0;   // Skip new trade above this spread (0 = off)
input bool    UseTimeFilter     = false;   // Limit trading hours (server time)
input int     StartHour         = 8;   // Start hour
input int     EndHour           = 22;   // End hour
input bool    FridayCloseAll    = false;   // Close everything before Friday close
input int     FridayCloseHour   = 21;   // Friday close hour

input string  __s7__            = "--- Misc ---";
input int     MagicNumber       = 13341;   // Magic number (unique per EA)
input int     SlippagePips      = 3;   // Slippage in pips
input string  TradeComment      = "MySignal";   // Order comment

//====================== ค่าคงที่สัญญาณ =============================
#define SIG_NONE  0
#define SIG_BUY   1
#define SIG_SELL  2
#define SIG_HOLD  3
#define SIG_CASH  4

#define P49_LOOKBACK 4
#define P49_TARGET   9

//====================== ตัวแปรภายใน ================================
double   g_ribF[], g_ribS[], g_de[], g_cnt[];
int      g_sig[];
int      g_size = 0;             // จำนวนแท่งที่คำนวณไว้ในอาร์เรย์

double   g_pip;                  // ขนาด 1 pip ในหน่วยราคา
double   g_slippage;
datetime g_lastBar   = 0;        // แท่งล่าสุดที่ตัดสินใจไปแล้ว
datetime g_calcBar   = 0;        // แท่งล่าสุดที่คำนวณสัญญาณไปแล้ว
datetime g_reducedAt = 0;        // เวลาเปิดของไม้ที่ปิดครึ่งไปแล้ว (กันลดซ้ำ)
                                 // ใช้เวลาเปิด ไม่ใช่เลขตั๋ว เพราะปิดครึ่งไม้แล้ว
                                 // MT4 ออกเลขตั๋วใหม่ให้ส่วนที่เหลือ

//+------------------------------------------------------------------+
int OnInit()
  {
   if(BbeFast < 1 || BbeSlow < 1 || BbeFast >= BbeSlow)
     {
      Print("Bad BBE inputs - must be positive and BbeFast < BbeSlow");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(DeFast < 1 || DeSlow < 1 || DeFast >= DeSlow || DeSmooth < 1)
     {
      Print("Bad DE inputs - must be positive and DeFast < DeSlow");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(CalcBars < 100)
     {
      Print("CalcBars must be at least 100");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(UseRiskPercent && (RiskPercent <= 0 || RiskPercent > 10))
     {
      Print("RiskPercent must be between 0 and 10");
      return(INIT_PARAMETERS_INCORRECT);
     }

   // โบรกเกอร์ 5 ทศนิยม (หรือทอง 3 ทศนิยม): 1 pip = 10 point
   g_pip = Point;
   if(Digits == 3 || Digits == 5)
      g_pip = Point * 10;
   g_slippage = SlippagePips * (g_pip / Point);

   Print(StringFormat("MySignal_EA started %s | BBE %d/%d | DE %d/%d | 1 pip = %s",
                      Symbol(), BbeFast, BbeSlow, DeFast, DeSlow,
                      DoubleToString(g_pip, Digits)));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   ManageOpenTrade();          // BE / trailing ต้องไว ทำทุก tick

   if(FridayCloseAll && DayOfWeek() == 5 && Hour() >= FridayCloseHour)
     {
      CloseAll("Friday close");
      return;
     }

   if(TradeOnBarClose)
     {
      if(g_lastBar == Time[0])
         return;
      g_lastBar = Time[0];
     }

   if(!Recalc())
      return;

   int sh  = (TradeOnBarClose ? 1 : 0);
   if(sh >= g_size)
      return;
   int sig = g_sig[sh];

   int ticket = FindOrder();
   int type   = (ticket > 0 ? OrderTypeOf(ticket) : -1);

   // 1) ถือไม้อยู่ — ดูว่าต้องออกหรือลดไหม
   if(ticket > 0)
     {
      if(CloseOnOpposite &&
         ((type == OP_BUY && sig == SIG_SELL) || (type == OP_SELL && sig == SIG_BUY)))
        {
         ClosePosition(ticket, 0);
         ticket = -1;
        }
      else
        {
         if(ReduceOnFade && type == OP_BUY && Fading(sh)
            && OrderSelect(ticket, SELECT_BY_TICKET)
            && OrderOpenTime() != g_reducedAt)
           {
            double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
            double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
            if(lotStep <= 0) lotStep = 0.01;
            double half = MathFloor(NormalizeDouble((OrderLots() / 2.0) / lotStep, 8)) * lotStep;
            if(half >= minLot && OrderLots() - half >= minLot)
              {
               Print("Status REDUCE - closing half ", DoubleToString(half, 2), " lot");
               g_reducedAt = OrderOpenTime();
               ClosePosition(ticket, NormalizeDouble(half, 2));
              }
           }
         return;               // ถือไม้อยู่ ไม่เปิดไม้ใหม่ซ้อน
        }
     }

   // 2) หาไม้ใหม่
   if(sig != SIG_BUY && sig != SIG_SELL)
      return;
   if(sig == SIG_SELL && !AllowShort)
      return;
   if(!PassSignalFilters(sig, sh))
      return;
   if(!PassFilters(sig, sh))
      return;
   if(!PassContext())
      return;

   bool confirmed = Confirmed(sig, sh);
   OpenTrade(sig == SIG_BUY ? OP_BUY : OP_SELL, confirmed);
  }

//+------------------------------------------------------------------+
//| คำนวณริบบิ้น / DE / นับ 1-9 / รหัสสัญญาณ ย้อนหลังทั้งชุด            |
//| ทำครั้งเดียวต่อแท่ง (สูตรเป็นแบบวนซ้ำ แยกคำนวณทีละแท่งไม่ได้)        |
//+------------------------------------------------------------------+
bool Recalc()
  {
   // เข้าเมื่อแท่งปิด = คำนวณครั้งเดียวต่อแท่งพอ
   // ถ้าเทรดกลางแท่ง ต้องคำนวณใหม่ทุก tick เพราะแท่ง 0 ยังขยับอยู่
   if(TradeOnBarClose && g_calcBar == Time[0] && g_size > 0)
      return(true);

   int warm  = BbeSlow * 4 + DeSlow + 10;
   int total = CalcBars + warm;
   if(total > Bars - 2)
      total = Bars - 2;
   if(total < warm + 20)
     {
      static bool warned = false;      // เตือนครั้งเดียว ไม่งั้นล็อกท่วมทุก tick
      if(!warned)
        {
         Print("Not enough bars (", Bars, ") - scroll left to load more history");
         warned = true;
        }
      return(false);
     }

   ArrayResize(g_ribF, total);
   ArrayResize(g_ribS, total);
   ArrayResize(g_de,   total);
   ArrayResize(g_cnt,  total);
   ArrayResize(g_sig,  total);
   g_size = total;

   double aF = 2.0 / (BbeFast + 1.0);
   double aS = 2.0 / (BbeSlow + 1.0);
   double aD = 2.0 / (DeSmooth + 1.0);

   int    seed = total - 1;
   double e1f  = Close[seed], e1s = Close[seed];
   g_ribF[seed] = Close[seed];
   g_ribS[seed] = Close[seed];
   g_de[seed]   = 0;
   g_cnt[seed]  = 0;
   g_sig[seed]  = SIG_CASH;

   for(int i = seed - 1; i >= 0; i--)
     {
      double c = Close[i];

      e1f        = aF * c   + (1 - aF) * e1f;
      g_ribF[i]  = aF * e1f + (1 - aF) * g_ribF[i+1];
      e1s        = aS * c   + (1 - aS) * e1s;
      g_ribS[i]  = aS * e1s + (1 - aS) * g_ribS[i+1];

      double raw = Vwma(i, DeFast) - Vwma(i, DeSlow);
      g_de[i]    = aD * raw + (1 - aD) * g_de[i+1];

      g_cnt[i] = 0;
      if(i + P49_LOOKBACK < Bars && c > Close[i + P49_LOOKBACK])
         g_cnt[i] = (g_cnt[i+1] >= P49_TARGET ? 1 : g_cnt[i+1] + 1);

      bool bull  = (g_ribF[i]   >= g_ribS[i]);
      bool bull1 = (g_ribF[i+1] >= g_ribS[i+1]);
      bool crossUp = (g_de[i] > 0 && g_de[i+1] <= 0);
      bool crossDn = (g_de[i] < 0 && g_de[i+1] >= 0);

      int code = (bull ? SIG_HOLD : SIG_CASH);
      if(bull && crossUp) code = SIG_BUY;
      if(bull && crossDn) code = SIG_SELL;
      if(bull && !bull1)  code = SIG_BUY;
      if(!bull && bull1)  code = SIG_SELL;
      g_sig[i] = code;
     }

   g_calcBar = Time[0];
   return(true);
  }

//+------------------------------------------------------------------+
double Vwma(const int i, const int n)
  {
   double num = 0, den = 0, sum = 0;
   int cnt = 0;

   for(int k = i; k < i + n && k < Bars; k++)
     {
      double v = (double)Volume[k];
      num += Close[k] * v;
      den += v;
      sum += Close[k];
      cnt++;
     }

   if(cnt == 0)
      return(0);
   if(den <= 0)
      return(sum / cnt);
   return(num / den);
  }

//+------------------------------------------------------------------+
//| ตัวยืนยันครบไหม (ใช้ตัดสินว่าเต็มไม้หรือครึ่งไม้)                    |
//+------------------------------------------------------------------+
bool Confirmed(const int sig, const int sh)
  {
   if(sh + 1 >= g_size)
      return(false);

   bool ok;
   if(sig == SIG_BUY)
      ok = (g_de[sh] > 0 && g_de[sh] >= g_de[sh+1]);
   else
      ok = (g_de[sh] < 0 && g_de[sh] <= g_de[sh+1]);

   if(ok && UseMcdFilter)
      ok = McdExpanding();

   return(ok);
  }

//+------------------------------------------------------------------+
//| MCD ฝั่งกำไรกำลังขยายไหม (อ่านจาก MySignal_MCD.ex4)                |
//| อ่านค่าไม่ได้ = ไม่ตัดสิน ปล่อยผ่าน                                  |
//+------------------------------------------------------------------+
bool McdExpanding()
  {
   int sh = (TradeOnBarClose ? 1 : 0);
   // บัฟเฟอร์ 8 = % ฝั่งกำไร · 5 = เส้นค่าเฉลี่ยของมันเอง (ดู MySignal_MCD.mq4)
   double p   = iCustom(NULL, 0, "MySignal_MCD", 600, 120, 0.08, 0.015, 10, false, 8, sh);
   double pma = iCustom(NULL, 0, "MySignal_MCD", 600, 120, 0.08, 0.015, 10, false, 5, sh);

   if(p == EMPTY_VALUE || pma == EMPTY_VALUE || p == 0 || pma == 0)
      return(true);
   return(p > pma);
  }

//+------------------------------------------------------------------+
//| สถานะ "ลดไม้" — ถือของอยู่แต่แรงเริ่มหมด                            |
//+------------------------------------------------------------------+
bool Fading(const int sh)
  {
   if(sh + 6 >= g_size)
      return(false);
   if(g_ribF[sh] < g_ribS[sh])       // ริบบิ้นแดงแล้ว = เรื่องของสัญญาณขาย
      return(false);

   bool deFading = (g_de[sh] > 0
                    && g_de[sh]   < g_de[sh+1]
                    && g_de[sh+1] < g_de[sh+2]
                    && g_de[sh+2] < g_de[sh+3]);
   bool counted  = (g_cnt[sh] >= P49_TARGET);

   double w0 = MathAbs(g_ribF[sh]   - g_ribS[sh]);
   double w5 = MathAbs(g_ribF[sh+5] - g_ribS[sh+5]);
   bool narrowing = (w5 > 0 && w0 < w5 * 0.85);

   return(deFading || counted || narrowing);
  }

//+------------------------------------------------------------------+
//| ตัวกรองที่มาจากตัว My Signal เอง                                   |
//+------------------------------------------------------------------+
bool PassSignalFilters(const int sig, const int sh)
  {
   if(RequireDeAbove0)
     {
      if(sig == SIG_BUY  && g_de[sh] <= 0) return(false);
      if(sig == SIG_SELL && g_de[sh] >= 0) return(false);
     }
   if(SkipWhenCount9 && sig == SIG_BUY && g_cnt[sh] >= P49_TARGET)
      return(false);
   if(UseMcdFilter && sig == SIG_BUY && !McdExpanding())
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| ตัวกรองทั่วไป                                                     |
//+------------------------------------------------------------------+
bool PassFilters(const int sig, const int sh)
  {
   if(UseTrendFilter)
     {
      double trend = iMA(NULL, 0, TrendEMA, 0, MODE_EMA, PRICE_CLOSE, sh);
      if(sig == SIG_BUY  && Close[sh] <= trend) return(false);
      if(sig == SIG_SELL && Close[sh] >= trend) return(false);
     }

   if(UseAdxFilter)
     {
      double adx = iADX(NULL, 0, AdxPeriod, PRICE_CLOSE, MODE_MAIN, sh);
      if(adx < AdxMin) return(false);
     }

   if(UseRibbonGapFilter)
     {
      double atr = iATR(NULL, 0, AtrPeriod, sh);
      double gap = MathAbs(g_ribF[sh] - g_ribS[sh]);
      if(atr <= 0 || gap < GapAtrMultiple * atr) return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
bool PassContext()
  {
   if(MaxSpreadPips > 0)
     {
      double spread = (Ask - Bid) / g_pip;
      if(spread > MaxSpreadPips)
        {
         Print(StringFormat("Skip - spread too wide %.1f pip", spread));
         return(false);
        }
     }

   if(UseTimeFilter)
     {
      int h = Hour();
      bool ok = (StartHour <= EndHour) ? (h >= StartHour && h < EndHour)
                                       : (h >= StartHour || h < EndHour);  // คร่อมเที่ยงคืน
      if(!ok) return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
void OpenTrade(const int cmd, const bool confirmed)
  {
   double slDist = StopDistance();
   if(slDist <= 0)
     {
      Print("Cannot compute SL distance - skipping");
      return;
     }

   double lots = LotSize(slDist);
   bool   half_used = false;
   if(!confirmed && HalfLotUnconfirmed && lots > 0)
     {
      double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
      double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
      if(lotStep <= 0) lotStep = 0.01;
      // NormalizeDouble ก่อน MathFloor — 0.03/0.01 ได้ 2.9999… ปัดลงจะเหลือ 0.02
      double half = MathFloor(NormalizeDouble((lots / 2.0) / lotStep, 8)) * lotStep;
      if(half >= minLot)
        {
         lots = NormalizeDouble(half, 2);
         half_used = true;
         Print("Not confirmed - half lot ", DoubleToString(lots, 2), " lot");
        }
      else
         Print("Not confirmed but half lot < minLot - using full lot");
     }
   if(lots <= 0)
     {
      Print("Cannot compute lot size - skipping");
      return;
     }

   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(slDist < stopLevel)
      slDist = stopLevel;

   double tpDist = TargetDistance();
   if(tpDist > 0 && tpDist < stopLevel)
      tpDist = stopLevel;

   double price = 0, sl = 0, tp = 0;

   for(int attempt = 0; attempt < 3; attempt++)
     {
      RefreshRates();
      price = (cmd == OP_BUY ? Ask : Bid);

      // คิด SL/TP ใหม่ทุกครั้งที่ลองส่ง — ราคาขยับไปแล้วหลัง Sleep
      tp = 0;
      if(cmd == OP_BUY)
        {
         sl = NormalizeDouble(price - slDist, Digits);
         if(tpDist > 0) tp = NormalizeDouble(price + tpDist, Digits);
        }
      else
        {
         sl = NormalizeDouble(price + slDist, Digits);
         if(tpDist > 0) tp = NormalizeDouble(price - tpDist, Digits);
        }

      int ticket = OrderSend(Symbol(), cmd, lots, NormalizeDouble(price, Digits),
                             (int)g_slippage, sl, tp, TradeComment,
                             MagicNumber, 0, (cmd == OP_BUY ? clrGreen : clrCrimson));
      if(ticket > 0)
        {
         Print(StringFormat("OPEN %s %.2f lot at %s | SL %s | TP %s | %s",
                            (cmd == OP_BUY ? "BUY" : "SELL"), lots,
                            DoubleToString(price, Digits),
                            DoubleToString(sl, Digits),
                            (tp > 0 ? DoubleToString(tp, Digits) : "-"),
                            (half_used ? "half" : "full")));
         return;
        }

      int err = GetLastError();
      Print(StringFormat("OrderSend failed (attempt %d) error %d", attempt + 1, err));
      if(err == ERR_NOT_ENOUGH_MONEY || err == ERR_TRADE_DISABLED ||
         err == ERR_INVALID_STOPS    || err == ERR_INVALID_TRADE_VOLUME)
         return;
      Sleep(500);
     }
  }

//+------------------------------------------------------------------+
double StopDistance()
  {
   if(UseAtrStops)
      return(iATR(NULL, 0, AtrPeriod, 1) * SlAtrMultiple);
   return(SlPips * g_pip);
  }

double TargetDistance()
  {
   if(UseAtrStops)
     {
      if(TpAtrMultiple <= 0) return(0);
      return(iATR(NULL, 0, AtrPeriod, 1) * TpAtrMultiple);
     }
   if(TpPips <= 0) return(0);
   return(TpPips * g_pip);
  }

//+------------------------------------------------------------------+
double LotSize(const double slDist)
  {
   double lots = FixedLots;

   if(UseRiskPercent)
     {
      double risk     = AccountBalance() * RiskPercent / 100.0;
      double tickVal  = MarketInfo(Symbol(), MODE_TICKVALUE);
      double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
      if(tickVal <= 0 || tickSize <= 0 || slDist <= 0)
         return(0);

      double lossPerLot = (slDist / tickSize) * tickVal;   // ขาดทุนต่อ 1 ล็อตถ้าโดน SL
      if(lossPerLot <= 0)
         return(0);
      lots = risk / lossPerLot;
     }

   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(lotStep <= 0) lotStep = 0.01;

   // NormalizeDouble ก่อนปัดลง — 0.03/0.01 ได้ 2.9999… ถ้าปัดเลยจะเหลือ 0.02
   lots = MathFloor(NormalizeDouble(lots / lotStep, 8)) * lotStep;
   if(lots > maxLot)  lots = maxLot;
   if(lots > MaxLots) lots = MaxLots;

   if(lots < minLot)
     {
      // ปัดขึ้นให้ถึง minLot = เสี่ยงเกิน RiskPercent ที่ตั้งไว้ ต้องบอกให้รู้
      Print(StringFormat("Computed lot %.4f is below minLot %.2f - using minLot "
                         "(this trade risks more than %.1f%%)", lots, minLot, RiskPercent));
      lots = minLot;
     }

   double need = MarketInfo(Symbol(), MODE_MARGINREQUIRED) * lots;
   if(need > AccountFreeMargin())
     {
      Print("Not enough margin for ", DoubleToString(lots, 2), " lot");
      return(0);
     }

   return(NormalizeDouble(lots, 2));
  }

//+------------------------------------------------------------------+
void ManageOpenTrade()
  {
   if(!UseBreakEven && !UseTrailing)
      return;

   int ticket = FindOrder();
   if(ticket <= 0 || !OrderSelect(ticket, SELECT_BY_TICKET))
      return;

   double open      = OrderOpenPrice();
   double sl        = OrderStopLoss();
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double atr       = iATR(NULL, 0, AtrPeriod, 1);
   double newSl     = sl;

   if(OrderType() == OP_BUY)
     {
      double profit = Bid - open;
      double risk   = (sl > 0 ? open - sl : StopDistance());

      if(UseBreakEven && risk > 0 && profit >= risk * BreakEvenAtR && sl < open)
         newSl = open;

      if(UseTrailing && atr > 0)
        {
         double trail = Bid - atr * TrailAtrMultiple;
         if(trail > newSl) newSl = trail;
        }

      newSl = NormalizeDouble(newSl, Digits);
      if(newSl > sl && Bid - newSl > stopLevel)
         ModifySl(ticket, newSl);
     }
   else if(OrderType() == OP_SELL)
     {
      double profit = open - Ask;
      double risk   = (sl > 0 ? sl - open : StopDistance());

      if(UseBreakEven && risk > 0 && profit >= risk * BreakEvenAtR && (sl == 0 || sl > open))
         newSl = open;

      if(UseTrailing && atr > 0)
        {
         double trail = Ask + atr * TrailAtrMultiple;
         if(newSl == 0 || trail < newSl) newSl = trail;
        }

      newSl = NormalizeDouble(newSl, Digits);
      if((sl == 0 || newSl < sl) && newSl - Ask > stopLevel)
         ModifySl(ticket, newSl);
     }
  }

//+------------------------------------------------------------------+
void ModifySl(const int ticket, const double newSl)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return;
   if(!OrderModify(ticket, OrderOpenPrice(), newSl, OrderTakeProfit(), 0, clrOrange))
      Print("OrderModify failed error ", GetLastError());
  }

//+------------------------------------------------------------------+
int FindOrder()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol())                   continue;
      if(OrderMagicNumber() != MagicNumber)           continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
         return(OrderTicket());
     }
   return(-1);
  }

int OrderTypeOf(const int ticket)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return(-1);
   return(OrderType());
  }

//+------------------------------------------------------------------+
//| ปิดไม้ — lots = 0 คือปิดทั้งไม้                                     |
//+------------------------------------------------------------------+
void ClosePosition(const int ticket, const double lots)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return;

   double vol = (lots > 0 ? lots : OrderLots());
   if(vol > OrderLots())
      vol = OrderLots();

   for(int attempt = 0; attempt < 3; attempt++)
     {
      RefreshRates();
      double price = (OrderType() == OP_BUY ? Bid : Ask);
      if(OrderClose(ticket, vol, NormalizeDouble(price, Digits),
                    (int)g_slippage, clrGray))
         return;
      Print("OrderClose failed error ", GetLastError());
      Sleep(500);
     }
  }

//+------------------------------------------------------------------+
void CloseAll(const string why)
  {
   for(int guard = 0; guard < 20; guard++)      // กันวนไม่รู้จบถ้าปิดไม่สำเร็จ
     {
      int ticket = FindOrder();
      if(ticket <= 0)
         return;
      Print("Close: ", why);
      ClosePosition(ticket, 0);
     }
  }
//+------------------------------------------------------------------+
