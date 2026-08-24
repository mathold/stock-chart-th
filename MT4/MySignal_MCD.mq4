//+------------------------------------------------------------------+
//|  MySignal_MCD.mq4                                                |
//|  MCD (Multicolor Dragon) — กระจายต้นทุนผู้ถือ 100% · หน้าต่างล่าง  |
//|                                                                  |
//|  แท่งรวมกันได้ 100 เรียงจากล่างขึ้นบน                               |
//|    เขียว  = ต้นทุนต่ำกว่าราคา (กำไร)                                |
//|    เหลือง = ต้นทุนใกล้ราคา   (ลอย)                                 |
//|    แดง    = ต้นทุนสูงกว่าราคา (ติดดอย)                              |
//|  เส้น MA10 สามเส้น: ม่วง = ฝั่งกำไร · ชมพู = ฝั่งลอย · ฟ้า = ติดดอย  |
//|                                                                  |
//|  วิธีคิด: ทุกแท่ง ต้นทุนเก่าถูกล้างตามอัตราเปลี่ยนมือ แล้วเติมต้นทุน  |
//|  ใหม่กระจายเท่า ๆ กันในช่วง Low-High ของแท่งนั้น                    |
//|                                                                  |
//|  ⚠ ของจริง (Homily) แยก "รายใหญ่/รายย่อย" จากขนาดคำสั่งซื้อขาย      |
//|    ซึ่ง MT4 ไม่มี — ที่นี่แยกจากราคาทุนเทียบราคาปัจจุบันแทน          |
//|    และวอลุ่มเป็น tick volume ตัวเลขจึงเป็นแนวโน้มคร่าว ๆ เท่านั้น     |
//|                                                                  |
//|  วางที่ MQL4 > Indicators แล้วกด F7 คอมไพล์                        |
//|  เป็นเครื่องมือช่วยดูกราฟ ไม่ใช่คำแนะนำการลงทุน                     |
//+------------------------------------------------------------------+
#property copyright "Mathold"
#property version   "1.00"
#property strict
#property indicator_separate_window
#property indicator_minimum 0
#property indicator_maximum 100
#property indicator_buffers 8
#property indicator_color1 clrFireBrick
#property indicator_color2 clrNONE
#property indicator_color3 clrGold
#property indicator_color4 clrNONE
#property indicator_color5 clrGreen
#property indicator_color6 clrMediumPurple
#property indicator_color7 clrHotPink
#property indicator_color8 clrDeepSkyBlue

input int    McdBars     = 600;    // คำนวณย้อนหลังกี่แท่ง (มากไปกราฟจะอืด)
input int    McdLevels   = 120;    // จำนวนช่องราคาที่ใช้เก็บต้นทุน
input double McdBand     = 0.08;   // ±8% รอบราคา = ช่วง "ลอย" (เหลือง)
input double McdTurnover = 0.015;  // อัตราเปลี่ยนมือฐาน (มาก = ลืมต้นทุนเก่าเร็ว)
input int    McdMa       = 10;     // คาบเส้นค่าเฉลี่ยสามเส้น
input bool   ShowMaLines = true;   // แสดงเส้น MA10

// แท่งซ้อนวางไว้ที่ 0 / 2 / 4 โดยมีบัฟเฟอร์เปล่าคั่น
// เพราะ MT4 จะจับ "ฮิสโตแกรมสองตัวที่ติดกัน" ไประบายสีระหว่างเส้น
// (ท่าเดียวกับที่ริบบิ้น BBE ใช้) ถ้าวาง 0-1-2 ติดกันแถบเหลืองจะหาย
double TrapBuf[], Gap1[], FloatBuf[], Gap2[], ProfitBuf[];  // 0-4 แท่งซ้อน
double PMA[], FMA[], LMA[];                                 // 5-7 เส้นค่าเฉลี่ย
double PBuf[], FBuf[], LBuf[];                              // 8-10 ค่าดิบแต่ละกลุ่ม

datetime g_lastBar = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(McdLevels < 20 || McdBand <= 0 || McdTurnover <= 0 || McdMa < 1)
     {
      Print("MySignal_MCD: ค่าอินพุตไม่ถูกต้อง");
      return(INIT_PARAMETERS_INCORRECT);
     }

   IndicatorShortName("MCD");
   IndicatorDigits(1);
   IndicatorBuffers(11);

   SetIndexBuffer(0, TrapBuf);   SetIndexBuffer(1, Gap1);
   SetIndexBuffer(2, FloatBuf);  SetIndexBuffer(3, Gap2);
   SetIndexBuffer(4, ProfitBuf); SetIndexBuffer(5, PMA);
   SetIndexBuffer(6, FMA);       SetIndexBuffer(7, LMA);
   SetIndexBuffer(8, PBuf);      SetIndexBuffer(9, FBuf);
   SetIndexBuffer(10, LBuf);

   // วาดแท่งสูงสุดก่อน (แดง) แล้วให้แท่งเตี้ยกว่าทับลงมา = ได้แถบซ้อน 100%
   SetIndexStyle(0, DRAW_HISTOGRAM, STYLE_SOLID, 2, clrFireBrick);
   SetIndexStyle(1, DRAW_NONE);
   SetIndexStyle(2, DRAW_HISTOGRAM, STYLE_SOLID, 2, clrGold);
   SetIndexStyle(3, DRAW_NONE);
   SetIndexStyle(4, DRAW_HISTOGRAM, STYLE_SOLID, 2, clrGreen);
   SetIndexStyle(5, (ShowMaLines ? DRAW_LINE : DRAW_NONE), STYLE_SOLID, 1, clrMediumPurple);
   SetIndexStyle(6, (ShowMaLines ? DRAW_LINE : DRAW_NONE), STYLE_SOLID, 1, clrHotPink);
   SetIndexStyle(7, (ShowMaLines ? DRAW_LINE : DRAW_NONE), STYLE_SOLID, 1, clrDeepSkyBlue);
   SetIndexStyle(8, DRAW_NONE);
   SetIndexStyle(9, DRAW_NONE);
   SetIndexStyle(10, DRAW_NONE);

   SetIndexLabel(0, "ติดดอย %");
   SetIndexLabel(1, NULL);
   SetIndexLabel(2, "ลอย+กำไร %");
   SetIndexLabel(3, NULL);
   SetIndexLabel(4, "กำไร %");
   SetIndexLabel(5, "MA กำไร");
   SetIndexLabel(6, "MA ลอย");
   SetIndexLabel(7, "MA ติดดอย");
   SetIndexLabel(8, NULL);
   SetIndexLabel(9, NULL);
   SetIndexLabel(10, NULL);

   for(int e = 0; e < 8; e++)
      SetIndexEmptyValue(e, EMPTY_VALUE);

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
   if(rates_total < 80)
      return(0);

   // สถานะ "ต้นทุนสะสม" ต่อเนื่องกันทั้งชุด แยกคำนวณทีละแท่งไม่ได้
   // จึงคำนวณใหม่ทั้งหน้าต่างเมื่อเปิดกราฟ หรือมีแท่งใหม่ (ไม่ทำทุก tick)
   if(prev_calculated > 0 && g_lastBar == time[0])
      return(rates_total);
   g_lastBar = time[0];

   int last = McdBars;
   if(last > rates_total - 2)
      last = rates_total - 2;
   if(last < 30)
      return(0);

   for(int j = rates_total - 1; j > last; j--)
     {
      TrapBuf[j] = EMPTY_VALUE;  FloatBuf[j] = EMPTY_VALUE;
      ProfitBuf[j] = EMPTY_VALUE;
      Gap1[j] = EMPTY_VALUE;  Gap2[j] = EMPTY_VALUE;
      PMA[j] = EMPTY_VALUE;  FMA[j] = EMPTY_VALUE;  LMA[j] = EMPTY_VALUE;
      PBuf[j] = 0;  FBuf[j] = 100;  LBuf[j] = 0;
     }

   // ── ขอบเขตราคาของหน้าต่างที่คำนวณ ──
   double lo = low[last], hi = high[last];
   for(int k = last; k >= 0; k--)
     {
      if(low[k]  < lo) lo = low[k];
      if(high[k] > hi) hi = high[k];
     }
   if(hi <= lo)
      return(rates_total);

   double pad   = (hi - lo) * 0.02;
   double edge0 = lo - pad;
   double width = ((hi + pad) - edge0) / McdLevels;
   if(width <= 0)
      return(rates_total);

   double chips[];
   double mid[];
   ArrayResize(chips, McdLevels);
   ArrayResize(mid,   McdLevels);
   ArrayInitialize(chips, 0.0);
   for(int m = 0; m < McdLevels; m++)
      mid[m] = edge0 + width * (m + 0.5);

   // ── ไล่จากแท่งเก่าสุดมาหาแท่งปัจจุบัน ──
   for(int i = last; i >= 0; i--)
     {
      double vol = (double)tick_volume[i];
      if(vol <= 0)
         vol = 1;

      // อัตราเปลี่ยนมือ ประมาณจากวอลุ่มวันนี้เทียบค่าเฉลี่ย 60 แท่ง
      double sum = 0;
      int    n   = 0;
      for(int a = i; a < i + 60 && a < rates_total; a++)
        {
         sum += (double)tick_volume[a];
         n++;
        }
      double avg  = (n > 0 && sum > 0 ? sum / n : vol);
      double turn = McdTurnover * vol / (avg > 0 ? avg : 1);
      if(turn < 0.005) turn = 0.005;
      if(turn > 0.20)  turn = 0.20;

      int b1 = (int)MathFloor((low[i]  - edge0) / width);
      int b2 = (int)MathFloor((high[i] - edge0) / width) + 1;
      if(b1 < 0) b1 = 0;
      if(b2 > McdLevels) b2 = McdLevels;
      if(b2 <= b1) b2 = (int)MathMin(b1 + 1, McdLevels);
      if(b1 >= McdLevels) b1 = McdLevels - 1;

      double add = vol * turn / (b2 - b1);
      for(int q = 0; q < McdLevels; q++)
         chips[q] *= (1 - turn);
      for(int r = b1; r < b2; r++)
         chips[r] += add;

      double total = 0;
      for(int t = 0; t < McdLevels; t++)
         total += chips[t];
      if(total <= 0)
        {
         PBuf[i] = 0;  FBuf[i] = 100;  LBuf[i] = 0;
        }
      else
        {
         // ขอบระหว่างกลุ่มไล่ระดับ ไม่ตัดคม ไม่งั้นแท่งจะกระตุกเป็นฟันปลา
         double w = close[i] * McdBand;
         if(w <= 0)
            w = width;
         double p = 0, l = 0;
         for(int s = 0; s < McdLevels; s++)
           {
            double wp = (close[i] - mid[s]) / w;
            double wl = (mid[s] - close[i]) / w;
            if(wp < 0) wp = 0;  if(wp > 1) wp = 1;
            if(wl < 0) wl = 0;  if(wl > 1) wl = 1;
            p += chips[s] * wp;
            l += chips[s] * wl;
           }
         PBuf[i] = p / total * 100.0;
         LBuf[i] = l / total * 100.0;
         FBuf[i] = 100.0 - PBuf[i] - LBuf[i];
         if(FBuf[i] < 0) FBuf[i] = 0;
        }

      // แท่งซ้อน: แดงเต็ม 100 → เหลืองถึง (กำไร+ลอย) → เขียวถึงกำไร
      TrapBuf[i]   = 100.0;
      FloatBuf[i]  = PBuf[i] + FBuf[i];
      ProfitBuf[i] = PBuf[i];
      Gap1[i]      = EMPTY_VALUE;
      Gap2[i]      = EMPTY_VALUE;

      // เส้นค่าเฉลี่ย (แท่งเก่ากว่าคำนวณไปแล้ว จึงเฉลี่ยย้อนหลังได้เลย)
      double sp = 0, sf = 0, sl = 0;
      int    cnt = 0;
      for(int u = i; u < i + McdMa && u <= last; u++)
        {
         sp += PBuf[u];  sf += FBuf[u];  sl += LBuf[u];
         cnt++;
        }
      if(cnt > 0)
        {
         PMA[i] = sp / cnt;
         FMA[i] = sf / cnt;
         LMA[i] = sl / cnt;
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
