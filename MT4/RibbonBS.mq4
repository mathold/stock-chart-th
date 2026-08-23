//+------------------------------------------------------------------+
//|  RibbonBS.mq4                                                    |
//|  ริบบิ้น EMA 25/75 + ป้าย B/S ตรงจุดที่ริบบิ้นเปลี่ยนสี            |
//|  เขียว = EMA เร็วอยู่เหนือ EMA ช้า (ขาขึ้น) · ชมพู = ขาลง          |
//|                                                                  |
//|  วิธีติดตั้ง                                                      |
//|    1. MT4 → File → Open Data Folder → MQL4 → Indicators          |
//|    2. ก๊อปไฟล์นี้วางไว้ → กลับไป MT4 → Navigator คลิกขวา Refresh   |
//|       (หรือเปิดใน MetaEditor แล้วกด F7 คอมไพล์)                   |
//|    3. ลากใส่กราฟ                                                  |
//|                                                                  |
//|  เป็นเครื่องมือช่วยดูกราฟ ไม่ใช่คำแนะนำการลงทุน                    |
//+------------------------------------------------------------------+
#property copyright "Mathold"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 4

//--- 0,1 = ริบบิ้นขาขึ้น (ฮิสโตแกรมระบายระหว่างสองเส้น)
//--- 2,3 = ริบบิ้นขาลง
#property indicator_color1 clrLimeGreen
#property indicator_color2 clrLimeGreen
#property indicator_color3 clrHotPink
#property indicator_color4 clrHotPink

//--- อินพุต ---------------------------------------------------------
input int   FastEMA        = 25;          // EMA เร็ว
input int   SlowEMA        = 75;          // EMA ช้า
input color RibbonUpColor  = clrLimeGreen; // สีริบบิ้นขาขึ้น
input color RibbonDnColor  = clrHotPink;   // สีริบบิ้นขาลง
input int   RibbonWidth    = 1;            // ความหนาแท่งริบบิ้น (1-3)
input bool  ShowLabels     = true;         // แสดงป้าย B/S
input int   LabelFontSize  = 11;           // ขนาดตัวอักษร B/S
input int   LabelGapPoints = 60;           // ระยะห่างป้ายจากแท่ง (point)

//--- บัฟเฟอร์ -------------------------------------------------------
double UpFast[], UpSlow[], DnFast[], DnSlow[];

const string LBL_PREFIX = "RibbonBS_";

//+------------------------------------------------------------------+
int OnInit()
  {
   if(FastEMA < 1 || SlowEMA < 1 || FastEMA >= SlowEMA)
     {
      Print("RibbonBS: ค่า EMA ไม่ถูกต้อง — ต้องเป็นบวก และ FastEMA < SlowEMA");
      return(INIT_PARAMETERS_INCORRECT);
     }

   IndicatorShortName(StringFormat("RibbonBS %d/%d", FastEMA, SlowEMA));
   IndicatorDigits(Digits);

   SetIndexBuffer(0, UpFast);
   SetIndexBuffer(1, UpSlow);
   SetIndexBuffer(2, DnFast);
   SetIndexBuffer(3, DnSlow);

   SetIndexStyle(0, DRAW_HISTOGRAM, STYLE_SOLID, RibbonWidth, RibbonUpColor);
   SetIndexStyle(1, DRAW_HISTOGRAM, STYLE_SOLID, RibbonWidth, RibbonUpColor);
   SetIndexStyle(2, DRAW_HISTOGRAM, STYLE_SOLID, RibbonWidth, RibbonDnColor);
   SetIndexStyle(3, DRAW_HISTOGRAM, STYLE_SOLID, RibbonWidth, RibbonDnColor);

   SetIndexLabel(0, "EMA" + (string)FastEMA + " (ขาขึ้น)");
   SetIndexLabel(1, "EMA" + (string)SlowEMA + " (ขาขึ้น)");
   SetIndexLabel(2, "EMA" + (string)FastEMA + " (ขาลง)");
   SetIndexLabel(3, "EMA" + (string)SlowEMA + " (ขาลง)");

   for(int i = 0; i < 4; i++)
      SetIndexEmptyValue(i, EMPTY_VALUE);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ClearLabels();
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
   int need = SlowEMA + 2;
   if(rates_total < need)
      return(0);

   // แท่งที่เก่าที่สุดที่คำนวณได้ (ดัชนีนับจากขวา 0 = แท่งปัจจุบัน)
   int oldest = rates_total - need;

   int limit;
   if(prev_calculated <= 0)
      limit = oldest;                       // รอบแรก คำนวณทั้งกราฟ
   else
      limit = MathMin(rates_total - prev_calculated + 1, oldest);

   double gap = LabelGapPoints * Point;

   for(int i = limit; i >= 0; i--)
     {
      double f  = iMA(NULL, 0, FastEMA, 0, MODE_EMA, PRICE_CLOSE, i);
      double s  = iMA(NULL, 0, SlowEMA, 0, MODE_EMA, PRICE_CLOSE, i);
      double f1 = iMA(NULL, 0, FastEMA, 0, MODE_EMA, PRICE_CLOSE, i + 1);
      double s1 = iMA(NULL, 0, SlowEMA, 0, MODE_EMA, PRICE_CLOSE, i + 1);

      bool bull  = (f >= s);
      bool bull1 = (f1 >= s1);

      UpFast[i] = EMPTY_VALUE;  UpSlow[i] = EMPTY_VALUE;
      DnFast[i] = EMPTY_VALUE;  DnSlow[i] = EMPTY_VALUE;

      if(bull) { UpFast[i] = f; UpSlow[i] = s; }
      else     { DnFast[i] = f; DnSlow[i] = s; }

      // แท่งที่ริบบิ้นเปลี่ยนสี = จุด B/S
      if(ShowLabels && bull != bull1)
         DrawLabel(bull, time[i], (bull ? low[i] - gap : high[i] + gap));
     }

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| วางตัวอักษร B หรือ S ไว้ที่แท่งนั้น                                |
//+------------------------------------------------------------------+
void DrawLabel(const bool bull, const datetime t, const double price)
  {
   string name = LBL_PREFIX + (string)(long)t;

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);

   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetString(0, name, OBJPROP_TEXT, (bull ? "B" : "S"));
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Black");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, LabelFontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, (bull ? RibbonUpColor : RibbonDnColor));
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, (bull ? ANCHOR_UPPER : ANCHOR_LOWER));
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
  }

//+------------------------------------------------------------------+
void ClearLabels()
  {
   for(int i = ObjectsTotal(0, -1, OBJ_TEXT) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, -1, OBJ_TEXT);
      if(StringFind(name, LBL_PREFIX, 0) == 0)
         ObjectDelete(0, name);
     }
  }
//+------------------------------------------------------------------+
