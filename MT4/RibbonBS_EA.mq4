//+------------------------------------------------------------------+
//|  RibbonBS_EA.mq4                                                 |
//|  EA ตามริบบิ้น EMA 25/75 — ตัดขึ้น = Buy · ตัดลง = Sell            |
//|  พร้อมตัวกรอง 4 ตัว เปิด/ปิดได้อิสระ เพื่อเอาไป backtest เทียบกัน   |
//|                                                                  |
//|  วิธีติดตั้ง                                                      |
//|    1. MT4 → File → Open Data Folder → MQL4 → Experts             |
//|    2. ก๊อปไฟล์นี้วางไว้ → MetaEditor กด F7 คอมไพล์                 |
//|    3. MT4 → Navigator → Expert Advisors → ลากใส่กราฟ              |
//|       ติ๊ก "Allow live trading" ด้วย                              |
//|                                                                  |
//|  *** ต้อง backtest (Strategy Tester) และรันบัญชีเดโมให้ผ่านก่อน   |
//|      ใช้เงินจริงเสมอ · ผลในอดีตไม่รับประกันอนาคต ***               |
//|      ไฟล์นี้เป็นเครื่องมือ ไม่ใช่คำแนะนำการลงทุน                    |
//+------------------------------------------------------------------+
#property copyright "Mathold"
#property version   "1.00"
#property strict

//====================== อินพุต =====================================
input string  __s1__            = "--- สัญญาณ ---";
input int     FastEMA           = 25;      // EMA เร็ว
input int     SlowEMA           = 75;      // EMA ช้า
input bool    TradeOnBarClose   = true;    // เข้าเมื่อแท่งปิดแล้วเท่านั้น (แนะนำ)
input bool    CloseOnOpposite   = true;    // ตัดกลับอีกทาง = ปิดไม้เดิม

input string  __s2__            = "--- ตัวกรอง (ปิดหมด = ตัดเส้นล้วน ๆ) ---";
input bool    UseTrendFilter    = false;   // 1. เทรนด์ใหญ่: Buy ต้องอยู่เหนือ EMA ยาว
input int     TrendEMA          = 200;     //    คาบ EMA เทรนด์ใหญ่
input bool    UseAdxFilter      = false;   // 2. ความแรง: ADX ต้องเกินค่าที่ตั้ง
input int     AdxPeriod         = 14;
input double  AdxMin            = 22.0;
input bool    UseRibbonGapFilter= false;   // 3. ริบบิ้นต้องกว้างพอ (กรองไซด์เวย์)
input double  GapAtrMultiple    = 0.25;    //    |EMAเร็ว-EMAช้า| > ค่านี้ x ATR
input bool    UseConfirmBars    = false;   // 4. ยืนยัน: ต้องอยู่ฝั่งเดิมกี่แท่งติด
input int     ConfirmBars       = 2;

input string  __s3__            = "--- หยุดขาดทุน / ทำกำไร ---";
input bool    UseAtrStops       = true;    // true = คิดจาก ATR · false = ใช้ค่าพิพคงที่
input int     AtrPeriod         = 14;
input double  SlAtrMultiple     = 2.0;     // SL = 2 x ATR
input double  TpAtrMultiple     = 4.0;     // TP = 4 x ATR (0 = ไม่ตั้ง TP)
input double  SlPips            = 300;     // ใช้เมื่อ UseAtrStops = false
input double  TpPips            = 600;     // 0 = ไม่ตั้ง TP
input bool    UseBreakEven      = false;   // เลื่อน SL มาที่ทุนเมื่อกำไรถึงเป้า
input double  BreakEvenAtR      = 1.0;     //   กำไรกี่เท่าของ SL ถึงเลื่อน
input bool    UseTrailing       = false;   // trailing stop ตาม ATR
input double  TrailAtrMultiple  = 2.0;

input string  __s4__            = "--- ขนาดไม้ / ความเสี่ยง ---";
input bool    UseRiskPercent    = true;    // true = คิดล็อตจาก % พอร์ต
input double  RiskPercent       = 1.0;     // เสี่ยงกี่ % ของพอร์ตต่อไม้
input double  FixedLots         = 0.01;    // ใช้เมื่อ UseRiskPercent = false
input double  MaxLots           = 5.0;     // เพดานล็อตกันพลาด

input string  __s5__            = "--- ตัวกรองบริบท ---";
input double  MaxSpreadPips     = 5.0;     // สเปรดกว้างกว่านี้ = ไม่เข้าไม้ใหม่ (0 = ไม่เช็ก)
input bool    UseTimeFilter     = false;   // จำกัดชั่วโมงเทรด (เวลาเซิร์ฟเวอร์)
input int     StartHour         = 8;
input int     EndHour           = 22;
input bool    FridayCloseAll    = false;   // ปิดไม้ทั้งหมดก่อนตลาดปิดศุกร์
input int     FridayCloseHour   = 21;

input string  __s6__            = "--- อื่น ๆ ---";
input int     MagicNumber       = 25075;   // เลขประจำ EA ตัวนี้ (อย่าซ้ำกับ EA อื่น)
input int     SlippagePips      = 3;
input string  TradeComment      = "RibbonBS";

//====================== ตัวแปรภายใน ================================
double   g_pip;          // ขนาด 1 pip ในหน่วยราคา
double   g_slippage;     // slippage ในหน่วย point
datetime g_lastBar = 0;  // แท่งล่าสุดที่ประมวลผลไปแล้ว

//+------------------------------------------------------------------+
int OnInit()
  {
   if(FastEMA < 1 || SlowEMA < 1 || FastEMA >= SlowEMA)
     {
      Print("ค่า EMA ไม่ถูกต้อง — ต้องเป็นบวกและ FastEMA < SlowEMA");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(UseRiskPercent && (RiskPercent <= 0 || RiskPercent > 10))
     {
      Print("RiskPercent ต้องอยู่ระหว่าง 0-10 %");
      return(INIT_PARAMETERS_INCORRECT);
     }

   // โบรกเกอร์ 5 ทศนิยม (หรือทอง 3 ทศนิยม): 1 pip = 10 point
   g_pip = Point;
   if(Digits == 3 || Digits == 5)
      g_pip = Point * 10;

   g_slippage = SlippagePips * (g_pip / Point);

   Print(StringFormat("RibbonBS_EA เริ่มทำงาน %s | EMA %d/%d | 1 pip = %s",
                      Symbol(), FastEMA, SlowEMA, DoubleToString(g_pip, Digits)));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   // ดูแลไม้ที่เปิดอยู่ทุก tick (BE / trailing ต้องไว)
   ManageOpenTrade();

   if(FridayCloseAll && DayOfWeek() == 5 && Hour() >= FridayCloseHour)
     {
      CloseAll("ปิดก่อนตลาดปิดศุกร์");
      return;
     }

   // ตัดสินใจเข้า/ออกครั้งเดียวต่อแท่ง
   if(TradeOnBarClose)
     {
      if(g_lastBar == Time[0])
         return;
      g_lastBar = Time[0];
     }

   int    signal = Signal();       // +1 = ตัดขึ้น, -1 = ตัดลง, 0 = ไม่มี
   int    ticket = FindOrder();
   int    type   = (ticket > 0 ? OrderTypeOf(ticket) : -1);

   // 1) ตัดกลับทาง → ปิดไม้เดิมก่อน
   if(CloseOnOpposite && ticket > 0 && signal != 0)
     {
      if((type == OP_BUY && signal < 0) || (type == OP_SELL && signal > 0))
        {
         ClosePosition(ticket);
         ticket = -1;
        }
     }

   if(signal == 0 || ticket > 0)   // ไม่มีสัญญาณ หรือถือไม้อยู่แล้ว
      return;
   if(!PassFilters(signal))
      return;
   if(!PassContext())
      return;

   OpenTrade(signal > 0 ? OP_BUY : OP_SELL);
  }

//+------------------------------------------------------------------+
//| สัญญาณตัดเส้น — ดูแท่งที่ปิดแล้ว (shift 1) ถ้าตั้ง TradeOnBarClose |
//+------------------------------------------------------------------+
int Signal()
  {
   int i = (TradeOnBarClose ? 1 : 0);

   double f  = Ema(FastEMA, i),   s  = Ema(SlowEMA, i);
   double f1 = Ema(FastEMA, i+1), s1 = Ema(SlowEMA, i+1);

   bool bull  = (f > s);
   bool bull1 = (f1 > s1);

   if(bull && !bull1)  return(1);
   if(!bull && bull1)  return(-1);
   return(0);
  }

//+------------------------------------------------------------------+
//| ตัวกรอง 4 ตัว — ผ่านทุกตัวที่เปิดไว้ถึงจะเข้า                       |
//+------------------------------------------------------------------+
bool PassFilters(const int signal)
  {
   int i = (TradeOnBarClose ? 1 : 0);

   // 1. เทรนด์ใหญ่ — ราคาปิดต้องอยู่ฝั่งเดียวกับ EMA ยาว
   if(UseTrendFilter)
     {
      double trend = Ema(TrendEMA, i);
      if(signal > 0 && Close[i] <= trend) return(false);
      if(signal < 0 && Close[i] >= trend) return(false);
     }

   // 2. ความแรงเทรนด์ — ADX ต้องเกินเกณฑ์
   if(UseAdxFilter)
     {
      double adx = iADX(NULL, 0, AdxPeriod, PRICE_CLOSE, MODE_MAIN, i);
      if(adx < AdxMin) return(false);
     }

   // 3. ริบบิ้นต้องกว้างพอเมื่อเทียบกับความผันผวน (กรองไซด์เวย์)
   if(UseRibbonGapFilter)
     {
      double atr = iATR(NULL, 0, AtrPeriod, i);
      double gap = MathAbs(Ema(FastEMA, i) - Ema(SlowEMA, i));
      if(atr <= 0 || gap < GapAtrMultiple * atr) return(false);
     }

   // 4. ยืนยัน — ราคาปิดต้องอยู่ฝั่งเดียวกันติดกันหลายแท่ง
   if(UseConfirmBars && ConfirmBars > 1)
     {
      for(int k = i; k < i + ConfirmBars; k++)
        {
         double f = Ema(FastEMA, k), s = Ema(SlowEMA, k);
         if(signal > 0 && !(f > s)) return(false);
         if(signal < 0 && !(f < s)) return(false);
        }
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| ตัวกรองบริบท: สเปรด + ชั่วโมงเทรด                                  |
//+------------------------------------------------------------------+
bool PassContext()
  {
   if(MaxSpreadPips > 0)
     {
      double spread = (Ask - Bid) / g_pip;
      if(spread > MaxSpreadPips)
        {
         Print(StringFormat("ข้ามไม้ — สเปรดกว้าง %.1f pip", spread));
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
//| เปิดไม้ใหม่                                                        |
//+------------------------------------------------------------------+
void OpenTrade(const int cmd)
  {
   double slDist = StopDistance();          // ระยะ SL ในหน่วยราคา
   if(slDist <= 0)
     {
      Print("คำนวณระยะ SL ไม่ได้ — ข้ามไม้นี้");
      return;
     }

   double lots = LotSize(slDist);
   if(lots <= 0)
     {
      Print("คำนวณล็อตไม่ได้ — ข้ามไม้นี้");
      return;
     }

   double price = (cmd == OP_BUY ? Ask : Bid);
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(slDist < stopLevel)
      slDist = stopLevel;

   double tpDist = TargetDistance();
   if(tpDist > 0 && tpDist < stopLevel)
      tpDist = stopLevel;

   double sl, tp = 0;
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

   for(int attempt = 0; attempt < 3; attempt++)
     {
      RefreshRates();
      price = (cmd == OP_BUY ? Ask : Bid);

      int ticket = OrderSend(Symbol(), cmd, lots, NormalizeDouble(price, Digits),
                             (int)g_slippage, sl, tp, TradeComment,
                             MagicNumber, 0, (cmd == OP_BUY ? clrGreen : clrCrimson));
      if(ticket > 0)
        {
         Print(StringFormat("เปิด %s %.2f lot ที่ %s | SL %s | TP %s",
                            (cmd == OP_BUY ? "BUY" : "SELL"), lots,
                            DoubleToString(price, Digits),
                            DoubleToString(sl, Digits),
                            (tp > 0 ? DoubleToString(tp, Digits) : "-")));
         return;
        }

      int err = GetLastError();
      Print(StringFormat("OrderSend ไม่สำเร็จ (ครั้งที่ %d) error %d", attempt + 1, err));
      if(err == ERR_NOT_ENOUGH_MONEY || err == ERR_TRADE_DISABLED ||
         err == ERR_INVALID_STOPS    || err == ERR_INVALID_TRADE_VOLUME)
         return;                          // แก้ด้วยการลองใหม่ไม่ได้
      Sleep(500);
     }
  }

//+------------------------------------------------------------------+
//| ระยะ SL / TP (หน่วยราคา)                                           |
//+------------------------------------------------------------------+
double StopDistance()
  {
   if(UseAtrStops)
     {
      double atr = iATR(NULL, 0, AtrPeriod, 1);
      return(atr * SlAtrMultiple);
     }
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
//| ขนาดล็อต — จาก % ความเสี่ยง หรือค่าคงที่                            |
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

      // ขาดทุนต่อ 1 ล็อต ถ้าโดน SL
      double lossPerLot = (slDist / tickSize) * tickVal;
      if(lossPerLot <= 0)
         return(0);
      lots = risk / lossPerLot;
     }

   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(lotStep <= 0) lotStep = 0.01;

   lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   if(lots > MaxLots) lots = MaxLots;

   // เช็กมาร์จิ้นพอไหม
   double need = MarketInfo(Symbol(), MODE_MARGINREQUIRED) * lots;
   if(need > AccountFreeMargin())
     {
      Print("มาร์จิ้นไม่พอสำหรับ ", DoubleToString(lots, 2), " lot");
      return(0);
     }

   return(NormalizeDouble(lots, 2));
  }

//+------------------------------------------------------------------+
//| ดูแลไม้ที่เปิดอยู่ — break-even / trailing                          |
//+------------------------------------------------------------------+
void ManageOpenTrade()
  {
   if(!UseBreakEven && !UseTrailing)
      return;

   int ticket = FindOrder();
   if(ticket <= 0 || !OrderSelect(ticket, SELECT_BY_TICKET))
      return;

   double open  = OrderOpenPrice();
   double sl    = OrderStopLoss();
   double point = Point;
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * point;
   double atr   = iATR(NULL, 0, AtrPeriod, 1);
   double newSl = sl;

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
      Print("OrderModify ไม่สำเร็จ error ", GetLastError());
  }

//+------------------------------------------------------------------+
//| หาไม้ของ EA ตัวนี้ในสัญลักษณ์นี้ (ถือทีละไม้)                       |
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
void ClosePosition(const int ticket)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return;

   for(int attempt = 0; attempt < 3; attempt++)
     {
      RefreshRates();
      double price = (OrderType() == OP_BUY ? Bid : Ask);
      if(OrderClose(ticket, OrderLots(), NormalizeDouble(price, Digits),
                    (int)g_slippage, clrGray))
         return;
      Print("OrderClose ไม่สำเร็จ error ", GetLastError());
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
      Print("ปิดไม้: ", why);
      ClosePosition(ticket);
     }
  }

//+------------------------------------------------------------------+
double Ema(const int period, const int shift)
  {
   return(iMA(NULL, 0, period, 0, MODE_EMA, PRICE_CLOSE, shift));
  }
//+------------------------------------------------------------------+
