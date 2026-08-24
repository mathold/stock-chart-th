//+------------------------------------------------------------------+
//|  MySignal_Telegram.mq4                                           |
//|  EA แจ้งเตือนอย่างเดียว — ไม่ส่งออเดอร์ ไม่แตะพอร์ตเลย              |
//|                                                                  |
//|  คำนวณสัญญาณชุดเดียวกับ MySignal.mq4 แล้วส่งเข้า Telegram         |
//|    · สัญญาณซื้อ / ขาย  (ริบบิ้นพลิก หรือ DE ตัดเส้น 0)              |
//|    · Pattern 49 นับได้ 1   = จุดซื้อตามคู่มือ Homily               |
//|    · Pattern 49 นับครบ 9  = ขาเดินมาสุดรอบ                        |
//|    · RSI(7) ถึงระดับที่ตั้ง = ซื้อมากเกินไป                          |
//|                                                                  |
//|  ⚠ MT4 ห้าม WebRequest() ในไฟล์ Indicator — ต้องเป็น EA เท่านั้น     |
//|    ตัวนี้จึงเป็น EA แต่ไม่มีคำสั่งซื้อขายอยู่ในโค้ดเลยแม้แต่บรรทัดเดียว |
//|                                                                  |
//|  เตรียมก่อนใช้ (ทำครั้งเดียว)                                      |
//|    1. Telegram หา @BotFather → /newbot → ได้ Bot Token           |
//|    2. ทักบอทตัวเอง 1 ข้อความ แล้วหา Chat ID จาก @userinfobot       |
//|    3. MT4 → Tools → Options → Expert Advisors                    |
//|       ติ๊ก "Allow WebRequest for listed URL"                      |
//|       เพิ่ม  https://api.telegram.org                             |
//|    4. ลากไฟล์นี้ใส่กราฟ ใส่ Token/ChatId ในช่อง Inputs             |
//|       เปิด AutoTrading ด้วย (ไม่งั้น EA ไม่ทำงาน)                  |
//|                                                                  |
//|  ลากใส่ได้หลายกราฟหลายสินค้าพร้อมกัน แต่ละกราฟเตือนของตัวเอง        |
//|  ข้อความเป็นภาษาอังกฤษ เพราะ MT4 บน Mac (Wine) จัดการไทยไม่ได้      |
//|                                                                  |
//|  เป็นเครื่องมือช่วยเตือน ไม่ใช่คำแนะนำการลงทุน                      |
//+------------------------------------------------------------------+
#property copyright "Mathold"
#property version   "1.00"
#property strict

//====================== อินพุต =====================================
// ⚠ คำอธิบายอินพุตต้องเป็นอังกฤษ — MT4 บน Mac (Wine) แสดงไทยเป็น ????

// ── Telegram ── Token กับ Chat ID เป็นความลับ พิมพ์ใส่เองในช่องนี้
input string __s1__          = "--- Telegram ---";
input bool   UseTelegram     = true;   // Send alerts to Telegram
input string BotToken        = "";     // Bot token from @BotFather
input string ChatId          = "";     // Your chat id from @userinfobot
input bool   SendTestOnStart = true;   // Send a test message when attached
input string TagText         = "";     // Optional tag put in front of every message

// ── เตือนเหตุการณ์ไหนบ้าง ──
input string __s2__          = "--- What to alert ---";
input bool   NotifyBuySell   = true;   // My Signal buy / sell signal
input bool   NotifyCount1    = true;   // Pattern 49 reached 1 (buy point)
input bool   NotifyCount9    = true;   // Pattern 49 reached 9 (run complete)
input bool   NotifyRsi       = true;   // RSI reached the level
input double RsiAlertLevel   = 84.0;   // RSI level to alert at
input int    RsiPeriod       = 7;      // RSI period

// ── ช่องทางสำรองในเครื่อง ──
input string __s3__          = "--- Local alerts ---";
input bool   AlsoPopup       = false;  // Popup window in MT4 as well
input bool   AlsoPush        = false;  // Push to MT4 mobile as well

// ── ค่าสัญญาณ ── ต้องตรงกับ MySignal.mq4 ไม่งั้นเตือนคนละจุดกับที่เห็นบนกราฟ
input string __s4__          = "--- Signal settings ---";
input int    BbeFast         = 13;     // Fast EMA (double smoothed)
input int    BbeSlow         = 34;     // Slow EMA (double smoothed)
input int    DeFast          = 13;     // Fast VWMA
input int    DeSlow          = 55;     // Slow VWMA
input int    DeSmooth        = 5;      // DE smoothing EMA
input int    CountLookback   = 4;      // Compare close with N bars ago
input int    CountMax        = 9;      // Count restarts after this
input int    CalcBars        = 300;    // Bars to calculate per pass

//====================== ค่าคงที่สัญญาณ =============================
#define SIG_BUY   1
#define SIG_SELL  2
#define SIG_HOLD  3
#define SIG_CASH  4

//====================== ตัวแปรภายใน ================================
double   g_ribF[], g_ribS[], g_de[], g_cnt[];
int      g_sig[];
int      g_size    = 0;
datetime g_lastBar = 0;

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
   if(CountLookback < 1 || CountMax < 2 || CalcBars < 50)
     {
      Print("Bad count inputs - CountLookback >= 1, CountMax >= 2, CalcBars >= 50");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(UseTelegram && (StringLen(BotToken) < 20 || StringLen(ChatId) < 3))
     {
      Print("Telegram is on but BotToken / ChatId is empty - fill them in the Inputs tab");
      return(INIT_PARAMETERS_INCORRECT);
     }

   Print(StringFormat("MySignal_Telegram started %s %s | telegram %s",
                      Symbol(), TFText(Period()), (UseTelegram ? "ON" : "off")));

   if(UseTelegram && SendTestOnStart)
     {
      string msg = StringFormat("%s %s - alert bot connected. Watching for signals.",
                                Symbol(), TFText(Period()));
      if(TelegramSend(msg))
         Print("Telegram test message sent OK");
      else
         Print("Telegram test message FAILED - see the message above for the reason");
     }
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   // ตัดสินใจครั้งเดียวต่อแท่ง — อ่านจากแท่งที่ปิดแล้วเสมอ
   // ไม่งั้นสัญญาณจะกลับไปกลับมาระหว่างแท่งแล้วสแปม Telegram
   if(g_lastBar == Time[0])
      return;
   g_lastBar = Time[0];

   if(!Recalc())
      return;

   int sh = 1;                        // แท่งที่เพิ่งปิด
   if(sh + CountLookback >= g_size)
      return;

   int    sig   = g_sig[sh];
   int    count = (int)g_cnt[sh];
   bool   bull  = (g_ribF[sh] >= g_ribS[sh]);
   double rsi   = iRSI(NULL, 0, RsiPeriod, PRICE_CLOSE, sh);
   double price = Close[sh];
   double need  = Close[sh + CountLookback];   // ต้องปิดเหนือค่านี้เลขถึงนับต่อ

   string head = StringFormat("%s %s | %s | ribbon %s",
                              Symbol(), TFText(Period()),
                              DoubleToString(price, Digits),
                              (bull ? "GREEN" : "RED"));

   // เก็บทุกเหตุการณ์ของแท่งนี้ไว้ก่อน แล้วส่งทีเดียว
   // ถ้ายิงทีละอันจะบล็อก OnTick ได้ถึง 4 ครั้ง (WebRequest รอได้อันละ 3 วิ)
   string ev = "";

   if(NotifyBuySell && sig == SIG_BUY)
      ev += "BUY signal (My Signal)\n";
   if(NotifyBuySell && sig == SIG_SELL)
      ev += "SELL signal (My Signal)\n";

   if(NotifyCount1 && count == 1)
      ev += StringFormat("Count 1 - new up run started (next close must beat %s)\n",
                         DoubleToString(need, Digits));

   if(NotifyCount9 && count >= CountMax)
      ev += StringFormat("Count %d - run complete, momentum may be spent\n", count);

   if(NotifyRsi && rsi >= RsiAlertLevel)
      ev += StringFormat("RSI(%d) %.1f reached %.1f - overbought\n",
                         RsiPeriod, rsi, RsiAlertLevel);

   if(StringLen(ev) > 0)
      Fire(ev + head);
  }

//+------------------------------------------------------------------+
//| ส่งออกทุกช่องทางที่เปิดไว้                                          |
//+------------------------------------------------------------------+
void Fire(const string body)
  {
   string msg = (StringLen(TagText) > 0 ? TagText + " | " + body : body);

   Print(msg);
   if(UseTelegram) TelegramSend(msg);
   if(AlsoPopup)   Alert(msg);
   if(AlsoPush)    SendNotification(msg);
  }

//+------------------------------------------------------------------+
//| ส่งข้อความเข้า Telegram ผ่าน Bot API                               |
//|                                                                  |
//| ต้องเปิด Tools > Options > Expert Advisors                        |
//|   ติ๊ก Allow WebRequest for listed URL + เพิ่ม                     |
//|   https://api.telegram.org                                        |
//| ไม่เปิด = WebRequest คืน -1 พร้อม error 4060                       |
//| หมายเหตุ: WebRequest ใช้ใน Strategy Tester ไม่ได้ คืน -1 เสมอ       |
//+------------------------------------------------------------------+
bool TelegramSend(const string text)
  {
   // Strategy Tester ใช้ WebRequest ไม่ได้ คืน -1 เสมอ ออกไปเลยไม่ต้องเสียเวลา
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
   // ไม่งั้น Telegram ได้ไบต์ขยะต่อท้ายแล้วตอบ 400 กลับมา
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
//| (ขึ้นบรรทัดใหม่ ช่องว่าง เครื่องหมาย ต้องเข้ารหัสหมด ไม่งั้น 400)      |
//+------------------------------------------------------------------+
string UrlEncode(const string src)
  {
   uchar  bytes[];
   string out = "";
   int    n = StringToCharArray(src, bytes, 0, -1, CP_UTF8);
   if(n > 0 && bytes[n - 1] == 0)
      n--;                                    // ตัด null ปิดท้าย

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
//| คำนวณริบบิ้น / DE / เลขนับ / รหัสสัญญาณ — สูตรเดียวกับ MySignal.mq4 |
//+------------------------------------------------------------------+
bool Recalc()
  {
   int warm  = (int)MathMax(CountLookback, BbeSlow * 4) + DeSlow + 10;
   int total = CalcBars + warm;
   if(total > Bars - 2)
      total = Bars - 2;
   if(total < warm + 20)
     {
      static bool warned = false;             // เตือนครั้งเดียว ไม่งั้นล็อกท่วม
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

      e1f       = aF * c   + (1 - aF) * e1f;
      g_ribF[i] = aF * e1f + (1 - aF) * g_ribF[i+1];
      e1s       = aS * c   + (1 - aS) * e1s;
      g_ribS[i] = aS * e1s + (1 - aS) * g_ribS[i+1];

      double raw = Vwma(i, DeFast) - Vwma(i, DeSlow);
      g_de[i]    = aD * raw + (1 - aD) * g_de[i+1];

      g_cnt[i] = 0;
      if(i + CountLookback < Bars && c > Close[i + CountLookback])
         g_cnt[i] = (g_cnt[i+1] >= CountMax ? 1 : g_cnt[i+1] + 1);

      bool bull    = (g_ribF[i]   >= g_ribS[i]);
      bool bull1   = (g_ribF[i+1] >= g_ribS[i+1]);
      bool crossUp = (g_de[i] > 0 && g_de[i+1] <= 0);
      bool crossDn = (g_de[i] < 0 && g_de[i+1] >= 0);

      int code = (bull ? SIG_HOLD : SIG_CASH);
      if(bull && crossUp) code = SIG_BUY;
      if(bull && crossDn) code = SIG_SELL;
      if(bull && !bull1)  code = SIG_BUY;
      if(!bull && bull1)  code = SIG_SELL;
      g_sig[i] = code;
     }

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
