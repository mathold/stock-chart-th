//+------------------------------------------------------------------+
//|  EA_No9.mq4                                                      |
//|  EA เดินตามเลขนับ Pattern 49 ของ My Signal                        |
//|                                                                  |
//|  เข้าไม้ (ต้องครบทั้งสองข้อ)                                       |
//|    · เลขนับขึ้นได้ 1                                              |
//|    · ริบบิ้น BBE เขียว                                            |
//|    → เปิด Buy 0.1 lot · ฝั่ง Sell ไม่เปิดเลย                       |
//|                                                                  |
//|  ออกไม้ (เข้าข้อใดข้อหนึ่ง)                                        |
//|    · เลขนับขึ้นถึง 9                                              |
//|    · RSI(7) >= 84            ← ซื้อมากเกินไป ออกก่อน               |
//|    · ศุกร์ตามเวลาที่ตั้ง                                           |
//|    · (ตัวเลือก) ริบบิ้นพลิกแดง · SL / TP คงที่                      |
//|                                                                  |
//|  ระหว่างที่ไม้ยังไม่ปิด เจอเลข 1 อีกก็ไม่เปิดซ้ำ                      |
//|  ปิดแล้วเจอเลข 1 รอบใหม่ = เริ่มรอบใหม่                            |
//|                                                                  |
//|  ไม่สนใจออเดอร์อื่นในพอร์ต — มองเฉพาะไม้ที่มี MagicNumber ของตัวเอง   |
//|  (ต้องไม่ซ้ำกับ EA ตัวอื่น ค่าเริ่มต้น 90009)                        |
//|                                                                  |
//|  วิธีติดตั้ง: File > Open Data Folder > MQL4 > Experts             |
//|              วางไฟล์ > MetaEditor F7 > ลากใส่กราฟ + AutoTrading    |
//|                                                                  |
//|  *** ต้อง backtest และรันเดโมให้ผ่านก่อนใช้เงินจริงเสมอ            |
//|      ผลในอดีตไม่รับประกันอนาคต · ไฟล์นี้ไม่ใช่คำแนะนำการลงทุน ***    |
//+------------------------------------------------------------------+
#property copyright "Mathold"
#property version   "1.40"
#property strict

//====================== อินพุต =====================================
// ⚠ คำอธิบายอินพุตต้องเป็นอังกฤษ — MT4 บน Mac (Wine) แสดงไทยเป็น ????

// ── เลขนับ Pattern 49 ── นับจากปิดเทียบปิดของ 4 แท่งก่อน · ครบ 9 เริ่มใหม่
input string __s1__            = "--- Pattern 49 count ---";
input int    CountLookback     = 4;      // Compare close with N bars ago
input int    CountMax          = 9;      // Count restarts after this
input int    EntryCount        = 1;      // Open buy when count equals this
input int    ExitCount         = 9;      // Close when count reaches this
input int    CalcBars          = 300;    // Bars to calculate per pass
input bool   TradeOnBarClose   = true;   // Act on closed bar only (recommended)

// ── ตัวกรองด้วยริบบิ้น BBE ── EMA ซ้อนสองชั้น ชุดเดียวกับ MySignal
input string __s2__            = "--- BBE ribbon filter ---";
input bool   RequireBullRibbon = true;   // Open only while ribbon is green
input bool   CloseOnRibbonRed  = false;  // Also close when ribbon turns red
input int    BbeFast           = 13;     // Fast EMA (double smoothed)
input int    BbeSlow           = 34;     // Slow EMA (double smoothed)

// ── ออกด้วย RSI ── ซื้อมากเกินไปก็ออก ไม่ต้องรอนับครบ 9
input string __s3__            = "--- RSI exit ---";
input bool   UseRsiExit        = true;   // Close when RSI reaches the level
input int    RsiPeriod         = 7;      // RSI period
input double RsiExitLevel      = 84.0;   // Close at RSI >= this

// ── ขนาดไม้ ── ล็อตคงที่ ไม่คิดจาก % ความเสี่ยง
input string __s4__            = "--- Position size ---";
input double Lots              = 0.1;    // Fixed lot size

// ── หยุดขาดทุน / ทำกำไร ── 0 = ไม่ตั้ง
input string __s5__            = "--- Stops (0 = off) ---";
input double SlPips            = 0;      // Stop loss in pips (0 = none)
input double TpPips            = 0;      // Take profit in pips (0 = none)

// ── ศุกร์ / บริบท ──
input string __s6__            = "--- Friday / context ---";
input bool   FridayCloseAll    = true;   // Close own trades on Friday
input int    FridayCloseHour   = 21;     // Friday close hour (server time)
input bool   NoNewAfterFriday  = true;   // No new entry after that hour
input double MaxSpreadPips     = 0;      // Skip entry above this spread (0 = off)

// ── Telegram ── รายงานทุกครั้งที่เปิด/ปิดออเดอร์จริง
//    ต้องเปิด Tools > Options > Expert Advisors > Allow WebRequest for listed URL
//    แล้วเพิ่ม  https://api.telegram.org  ก่อน ไม่งั้นส่งไม่ออก (error 4060)
input string __s7__            = "--- Telegram ---";
input bool   UseTelegram       = false;  // Report trades to Telegram
input string BotToken          = "";     // Bot token from @BotFather
input string ChatId            = "";     // Your chat id from @userinfobot
input bool   SendTestOnStart   = true;   // Send a test message when attached

// ── อื่น ๆ ──
input string __s8__            = "--- Misc ---";
input int    MagicNumber       = 90009;  // Magic number (must be unique)
input int    SlippagePips      = 3;      // Slippage in pips
input string TradeComment      = "No9";  // Order comment
input bool   PrintDebug        = true;   // Log count changes

//====================== ตัวแปรภายใน ================================
double   g_cnt[];              // เลขนับของแต่ละแท่ง (ดัชนี 0 = แท่งปัจจุบัน)
double   g_ribF[], g_ribS[];   // ริบบิ้น BBE เส้นเร็ว / เส้นช้า
int      g_size    = 0;
double   g_pip;
double   g_slippage;
datetime g_lastBar = 0;        // แท่งล่าสุดที่ตัดสินใจไปแล้ว
datetime g_calcBar = 0;        // แท่งล่าสุดที่คำนวณไปแล้ว
int      g_lastLogged = -1;    // เลขนับล่าสุดที่เขียน log ไปแล้ว

//+------------------------------------------------------------------+
int OnInit()
  {
   if(CountLookback < 1 || CountMax < 2)
     {
      Print("Bad count inputs - CountLookback >= 1 and CountMax >= 2");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(EntryCount < 1 || EntryCount > CountMax || ExitCount < 1 || ExitCount > CountMax)
     {
      Print("EntryCount / ExitCount must be between 1 and CountMax");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(EntryCount >= ExitCount)
     {
      Print("EntryCount must be smaller than ExitCount");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(BbeFast < 1 || BbeSlow < 1 || BbeFast >= BbeSlow)
     {
      Print("Bad BBE inputs - must be positive and BbeFast < BbeSlow");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(UseRsiExit && (RsiPeriod < 2 || RsiExitLevel <= 50 || RsiExitLevel > 100))
     {
      Print("Bad RSI inputs - RsiPeriod >= 2 and RsiExitLevel between 50 and 100");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(Lots <= 0)
     {
      Print("Lots must be greater than 0");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(CalcBars < 50)
     {
      Print("CalcBars must be at least 50");
      return(INIT_PARAMETERS_INCORRECT);
     }

   // โบรก 5 ทศนิยม (หรือทอง 3 ทศนิยม): 1 pip = 10 point
   g_pip = Point;
   if(Digits == 3 || Digits == 5)
      g_pip = Point * 10;
   g_slippage = SlippagePips * (g_pip / Point);

   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   if(Lots < minLot || Lots > maxLot)
     {
      Print(StringFormat("Lots %.2f is outside broker range %.2f - %.2f",
                         Lots, minLot, maxLot));
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(UseTelegram && (StringLen(BotToken) < 20 || StringLen(ChatId) < 3))
     {
      Print("Telegram is on but BotToken / ChatId is empty - fill them in the Inputs tab");
      return(INIT_PARAMETERS_INCORRECT);
     }

   Print(StringFormat("EA No9 started %s | buy at count %d | close at count %d | %.2f lot | magic %d",
                      Symbol(), EntryCount, ExitCount, Lots, MagicNumber));
   Print(StringFormat("   ribbon filter %s | close on red %s | RSI exit %s",
                      (RequireBullRibbon ? "ON" : "off"),
                      (CloseOnRibbonRed  ? "ON" : "off"),
                      (UseRsiExit ? StringFormat("ON (RSI%d >= %.1f)",
                                                 RsiPeriod, RsiExitLevel) : "off")));

   if(UseTelegram && SendTestOnStart)
     {
      if(TelegramSend(StringFormat("EA No9 attached to %s %s - lot %.2f, magic %d",
                                   Symbol(), TFText(Period()), Lots, MagicNumber)))
         Print("Telegram test message sent OK");
      else
         Print("Telegram test message FAILED - see the message above for the reason");
     }
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   // ── 1. ศุกร์ตามเวลาที่ตั้ง → ปิดเฉพาะไม้ของ EA ตัวนี้ ──
   bool fridayStop = (FridayCloseAll && DayOfWeek() == 5 && Hour() >= FridayCloseHour);
   if(fridayStop)
     {
      CloseOwnTrade("Friday close");
      if(NoNewAfterFriday)
         return;                     // ไม่เปิดไม้ใหม่จนกว่าจะข้ามสัปดาห์
     }

   // ── 2. ตัดสินใจครั้งเดียวต่อแท่ง ──
   if(TradeOnBarClose)
     {
      if(g_lastBar == Time[0])
         return;
      g_lastBar = Time[0];
     }

   if(!Recalc())
      return;

   int sh = (TradeOnBarClose ? 1 : 0);
   if(sh + 1 >= g_size)
      return;

   int    count = (int)g_cnt[sh];
   bool   bull  = (g_ribF[sh] >= g_ribS[sh]);
   bool   bull1 = (g_ribF[sh+1] >= g_ribS[sh+1]);
   double rsi   = iRSI(NULL, 0, RsiPeriod, PRICE_CLOSE, sh);

   if(PrintDebug && count != g_lastLogged)
     {
      g_lastLogged = count;
      Print(StringFormat("count = %d | ribbon %s | RSI %.1f | close %s", count,
                         (bull ? "green" : "red"), rsi,
                         DoubleToString(Close[sh], Digits)));
     }

   int ticket = FindOwnOrder();

   // ── 3. ถือไม้อยู่ → เช็กทางออกทั้งสาม ──
   if(ticket > 0)
     {
      if(count >= ExitCount)
        {
         Print(StringFormat("count reached %d - closing", count));
         CloseOwnTrade(StringFormat("count %d", count));
        }
      else if(UseRsiExit && rsi >= RsiExitLevel)
        {
         Print(StringFormat("RSI %.1f reached %.1f - closing", rsi, RsiExitLevel));
         CloseOwnTrade(StringFormat("RSI %.1f", rsi));
        }
      else if(CloseOnRibbonRed && !bull && bull1)
        {
         Print("ribbon turned red - closing");
         CloseOwnTrade("ribbon red");
        }
      return;                        // ไม่เปิดซ้ำระหว่างถือไม้ (ตามกติกา)
     }

   // ── 4. ไม่มีไม้ → เจอเลขเริ่มนับก็เปิด Buy ──
   if(count != EntryCount)
      return;
   if(RequireBullRibbon && !bull)
     {
      if(PrintDebug)
         Print("count 1 but ribbon is red - skipped");
      return;
     }
   if(fridayStop && NoNewAfterFriday)
      return;
   if(!SpreadOk())
      return;

   OpenBuy(count);
  }

//+------------------------------------------------------------------+
//| คำนวณเลขนับ + ริบบิ้น BBE ย้อนหลังทั้งชุด                          |
//|   เลขนับ : ปิดสูงกว่าปิดของ N แท่งก่อน → +1 · ไม่ใช่ → 0             |
//|            ครบ CountMax แล้วแท่งถัดไปเริ่มที่ 1 ใหม่                |
//|   ริบบิ้น : EMA ซ้อนสองชั้น เร็ว/ช้า (สูตรเดียวกับ MySignal.mq4)     |
//| ทั้งคู่เป็นสูตรวนซ้ำ ต้องไล่จากแท่งเก่ามาหาแท่งใหม่ ทำครั้งเดียวต่อแท่ง |
//| (RSI ไม่ต้องคำนวณเอง MT4 มี iRSI ให้อยู่แล้ว)                       |
//+------------------------------------------------------------------+
bool Recalc()
  {
   if(TradeOnBarClose && g_calcBar == Time[0] && g_size > 0)
      return(true);

   int warm  = (int)MathMax(CountLookback, BbeSlow * 4) + 10;
   int total = CalcBars + warm;
   if(total > Bars - 2)
      total = Bars - 2;
   if(total < warm + 20)
     {
      static bool warned = false;    // เตือนครั้งเดียว ไม่งั้นล็อกท่วม
      if(!warned)
        {
         Print("Not enough bars (", Bars, ") - scroll left to load more history");
         warned = true;
        }
      return(false);
     }

   ArrayResize(g_cnt,  total);
   ArrayResize(g_ribF, total);
   ArrayResize(g_ribS, total);
   g_size = total;

   double aF = 2.0 / (BbeFast + 1.0);
   double aS = 2.0 / (BbeSlow + 1.0);

   int    seed = total - 1;
   double e1f  = Close[seed], e1s = Close[seed];
   g_cnt[seed]  = 0;
   g_ribF[seed] = Close[seed];
   g_ribS[seed] = Close[seed];

   for(int i = seed - 1; i >= 0; i--)
     {
      double c = Close[i];

      e1f       = aF * c   + (1 - aF) * e1f;
      g_ribF[i] = aF * e1f + (1 - aF) * g_ribF[i+1];
      e1s       = aS * c   + (1 - aS) * e1s;
      g_ribS[i] = aS * e1s + (1 - aS) * g_ribS[i+1];

      g_cnt[i] = 0;
      if(i + CountLookback < Bars && c > Close[i + CountLookback])
         g_cnt[i] = (g_cnt[i+1] >= CountMax ? 1 : g_cnt[i+1] + 1);
     }

   g_calcBar = Time[0];
   return(true);
  }

//+------------------------------------------------------------------+
bool SpreadOk()
  {
   if(MaxSpreadPips <= 0)
      return(true);

   double spread = (Ask - Bid) / g_pip;
   if(spread > MaxSpreadPips)
     {
      Print(StringFormat("Skip - spread too wide %.1f pip", spread));
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| เปิด Buy ล็อตคงที่                                                 |
//+------------------------------------------------------------------+
void OpenBuy(const int count)
  {
   double need = MarketInfo(Symbol(), MODE_MARGINREQUIRED) * Lots;
   if(need > AccountFreeMargin())
     {
      Print("Not enough margin for ", DoubleToString(Lots, 2), " lot");
      return;
     }

   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double slDist = SlPips * g_pip;
   double tpDist = TpPips * g_pip;
   if(slDist > 0 && slDist < stopLevel) slDist = stopLevel;
   if(tpDist > 0 && tpDist < stopLevel) tpDist = stopLevel;

   for(int attempt = 0; attempt < 3; attempt++)
     {
      RefreshRates();
      double price = Ask;

      // คิด SL/TP ใหม่ทุกครั้งที่ลองส่ง — ราคาขยับไปแล้วหลัง Sleep
      double sl = 0, tp = 0;
      if(slDist > 0) sl = NormalizeDouble(price - slDist, Digits);
      if(tpDist > 0) tp = NormalizeDouble(price + tpDist, Digits);

      int ticket = OrderSend(Symbol(), OP_BUY, Lots, NormalizeDouble(price, Digits),
                             (int)g_slippage, sl, tp, TradeComment,
                             MagicNumber, 0, clrGreen);
      if(ticket > 0)
        {
         string logline = StringFormat("OPEN BUY %.2f lot at %s | count %d | SL %s | TP %s",
                                      Lots, DoubleToString(price, Digits), count,
                                      (sl > 0 ? DoubleToString(sl, Digits) : "-"),
                                      (tp > 0 ? DoubleToString(tp, Digits) : "-"));
         Print(logline);
         if(UseTelegram)
            TelegramSend(StringFormat("EA No9 %s %s\n%s",
                                      Symbol(), TFText(Period()), logline));
         return;
        }

      int err = GetLastError();
      Print(StringFormat("OrderSend failed (attempt %d) error %d", attempt + 1, err));
      if(err == ERR_NOT_ENOUGH_MONEY || err == ERR_TRADE_DISABLED ||
         err == ERR_INVALID_STOPS    || err == ERR_INVALID_TRADE_VOLUME)
         return;                     // แก้ด้วยการลองใหม่ไม่ได้
      Sleep(500);
     }
  }

//+------------------------------------------------------------------+
//| หาไม้ของ EA ตัวนี้เท่านั้น — Symbol + MagicNumber                   |
//| ออเดอร์อื่นในพอร์ต (มือ หรือ EA ตัวอื่น) จะไม่ถูกแตะเลย              |
//+------------------------------------------------------------------+
int FindOwnOrder()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol())                   continue;
      if(OrderMagicNumber() != MagicNumber)           continue;
      if(OrderType() == OP_BUY)
         return(OrderTicket());
     }
   return(-1);
  }

//+------------------------------------------------------------------+
void CloseOwnTrade(const string why)
  {
   for(int guard = 0; guard < 20; guard++)   // กันวนไม่รู้จบถ้าปิดไม่สำเร็จ
     {
      int ticket = FindOwnOrder();
      if(ticket <= 0)
         return;
      if(!OrderSelect(ticket, SELECT_BY_TICKET))
         return;

      // อ่านค่าไว้ก่อนปิดเป็นตัวสำรอง เผื่ออ่านจากประวัติไม่ได้
      double lots   = OrderLots();
      double openPx = OrderOpenPrice();
      double pnl    = OrderProfit() + OrderSwap() + OrderCommission();

      bool done = false;
      for(int attempt = 0; attempt < 3 && !done; attempt++)
        {
         RefreshRates();
         if(OrderClose(ticket, lots, NormalizeDouble(Bid, Digits),
                       (int)g_slippage, clrGray))
           {
            Print("CLOSE BUY | ", why);

            // ปิดแล้วเลือกตั๋วเดิมซ้ำได้จากประวัติ — จะได้กำไร "จริง" หลังหักค่าคอม
            // และราคาที่ปิดได้จริง ไม่ใช่ Bid ตอนสั่ง
            double realized = pnl, exitPx = Bid;
            if(OrderSelect(ticket, SELECT_BY_TICKET))
              {
               realized = OrderProfit() + OrderSwap() + OrderCommission();
               exitPx   = OrderClosePrice();
              }

            if(UseTelegram)
               TelegramSend(StringFormat("EA No9 %s %s\nCLOSE BUY %.2f lot | %s\n" +
                                         "entry %s exit %s | P/L %.2f %s",
                                         Symbol(), TFText(Period()), lots, why,
                                         DoubleToString(openPx, Digits),
                                         DoubleToString(exitPx, Digits),
                                         realized, AccountCurrency()));
            done = true;
           }
         else
           {
            Print("OrderClose failed error ", GetLastError());
            Sleep(500);
           }
        }
      if(!done)
         return;                              // ปิดไม่ได้จริง ๆ ออกไปลองรอบ tick หน้า
     }
  }

//+------------------------------------------------------------------+
//| ส่งข้อความเข้า Telegram ผ่าน Bot API                               |
//|                                                                  |
//| ต้องเปิด Tools > Options > Expert Advisors                        |
//|   ติ๊ก Allow WebRequest for listed URL + เพิ่ม                     |
//|   https://api.telegram.org                                        |
//| ไม่เปิด = WebRequest คืน -1 พร้อม error 4060                       |
//| หมายเหตุ: WebRequest ใช้ใน Strategy Tester ไม่ได้ คืน -1 เสมอ       |
//| (โค้ดชุดนี้ก๊อปมาจาก MySignal_Telegram.mq4 ตั้งใจให้ไฟล์นี้อยู่ได้เอง  |
//|  ไม่ต้องพึ่ง #include แก้ที่ไหนต้องแก้ให้ตรงกันทั้งสองไฟล์)           |
//+------------------------------------------------------------------+
bool TelegramSend(const string text)
  {
   // Strategy Tester ใช้ WebRequest ไม่ได้ คืน -1 เสมอ — ไม่งั้น log ท่วมตอน optimize
   if(IsTesting() || IsOptimization() || IsVisualMode())
      return(false);
   if(StringLen(BotToken) < 20 || StringLen(ChatId) < 3)
     {
      Print("Telegram: BotToken / ChatId is empty");
      return(false);
     }

   string url  = "https://api.telegram.org/bot" + BotToken + "/sendMessage";
   string body = "chat_id=" + UrlEncode(ChatId)
               + "&disable_web_page_preview=true"
               + "&text=" + UrlEncode(text);

   char   data[], result[];
   string resultHeaders;
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";

   // StringToCharArray แถม null ปิดท้ายมาด้วย ต้องตัดทิ้งก่อนส่ง
   int n = StringToCharArray(body, data, 0, StringLen(body));
   if(n > 0 && data[n - 1] == 0)
      n--;
   ArrayResize(data, n);

   ResetLastError();
   int res = WebRequest("POST", url, headers, 3000, data, result, resultHeaders);

   if(res == -1)
     {
      int err = GetLastError();
      Print(StringFormat("Telegram WebRequest failed, error %d%s", err,
                         (err == 4060
                          ? " - add https://api.telegram.org in Tools > Options > Expert Advisors"
                          : "")));
      return(false);
     }
   if(res != 200)
     {
      Print(StringFormat("Telegram HTTP %d: %s", res,
                         CharArrayToString(result, 0, (int)MathMin(ArraySize(result), 300))));
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| แปลงข้อความเป็น percent-encoding แบบ UTF-8                        |
//+------------------------------------------------------------------+
string UrlEncode(const string src)
  {
   uchar  bytes[];
   string out = "";
   int    n = StringToCharArray(src, bytes, 0, -1, CP_UTF8);
   if(n > 0 && bytes[n - 1] == 0)
      n--;

   for(int i = 0; i < n; i++)
     {
      uchar c = bytes[i];
      if((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') ||
         (c >= 'a' && c <= 'z') || c == '-' || c == '_' || c == '.' || c == '~')
         out += CharToStr(c);
      else
         out += StringFormat("%%%02X", c);
     }
   return(out);
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
