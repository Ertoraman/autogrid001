//+------------------------------------------------------------------+
//|                                           Rectangle_Pattern_Bot.mq5|
//|  Rectangle Chart Pattern - MT5 ROBOT (EA) - Tam Otomatik        |
//|                                                                  |
//|  Kaynak: Trading Strategy Guides - "Rectangle Chart Pattern"     |
//|  https://tradingstrategyguides.com/rectangle-chart-pattern-strategy/|
//|                                                                  |
//|  Bu bir UZMAN DANIŞMAN (robot) dosyasıdır; gösterge değildir.    |
//|  Grafiğe eklenir, sinyal geldiğinde emir açar ve kapatır.        |
//|  Manuel müdahale gerekmez; tüm kararlar kapanmış mumlarda alınır.|
//|                                                                  |
//|  MAKALENİN 6 ADIMI (SELL örneği; BUY tam tersi):                  |
//|   1) Onceki trendi tespit et. SELL icin DÜŞÜŞ trendi gerekir.     |
//|      (En yuksek olasilikli islem, hakim trend yonundedir.)       |
//|   2) Dikdörtgeni tespit et: fiyat, yatay destek (alt) ve         |
//|      direnc (ust) cizgileri arasinda hareket eder. En az iki      |
//|      esit/yakin dip ve tepe gerekir.                             |
//|   3) Direnc uzerinde SAHTE kirilim (false breakout) bekle.       |
//|      "Secret sauce": trend yonundeki stop'lar temizlenir,        |
//|      kirilim alan alicilar tuzağa duser, asagi momentum beslenir.|
//|   4) Kirilim mumu KAPANIŞIYLA gir. SELL: kapanis destek altina   |
//|      inince sat. Yon tahmini yapma, fiyat soylesin.              |
//|   5) TP = dikdortgen yuksekliginin 2-3 kati (ustten alta olculur)|
//|   6) SL, dikdortgen direnc seviyesinin hafif uzerine (SELL).     |
//|      BUY'da SL destek altina, TP yukseklik kati uste.            |
//|                                                                  |
//|  TASARIM KARARLARI (makalede öznel kalan noktalar - ayrıntı     |
//|  README_Rectangle_Bot.md'de):                                    |
//|   * "Hakim trend" = EMA(fast) / EMA(slow) iliskisi + kapanisin   |
//|     EMA(slow) uzerinde/altinda olmasi (makale gosterge vermez).  |
//|   * "Dikdortgen" = son N mumda en yuksek tepe / en dusuk dip;    |
//|     her iki tarafta en az InpMinTouches temas, temaslar arasi    |
//|     en az InpMinDurationBars, iki yari arasi yataylik kontrolu.  |
//|   * "Sahte kirilim" = fitili tampon kadar direnc/destek disina   |
//|     tasan ama kapanisi tekrar iceri donen mum.                  |
//|   * Sahte kirilim olmadan gercek kirilim gelirse islem YOK      |
//|     (InpRequireFalseBreakout=true iken; makalenin ana filtresi). |
//|   * Giris, kirilim mumu kapandiktan sonraki ilk tick'te piyasa   |
//|     emriyle yapilir; TP/SL broker seviyesi olarak acilir.        |
//|                                                                  |
//|  GÜVENLİK: Sinyaller YALNIZCA KAPANMIŞ mumlarda değerlendirilir.|
//|  Tek pozisyon (varsayılan), spread filtresi, risk % lot hesabı,  |
//|  günlük limit, işlem saatleri ve para/süre çıkışları dahili.     |
//|  Önce Strategy Tester'da test edin. Yatırım tavsiyesi değildir.|
//+------------------------------------------------------------------+
#property copyright "Rectangle Chart Pattern - MT5 Robot"
#property version   "1.00"
#property strict
#property description "Rectangle Chart Pattern (Trading Strategy Guides) tam otomatik MT5 robotu"
#property description "Trend + yatay dikdortgen + sahte kirilim + kapanis kirilimi ile giris"
#property description "TP: dikdortgen yuksekliginin 2-3 kati | SL: direnc/destek disi tampon"
#property description "Sinyaller yalnizca kapanmis mumlarda degerlendirilir"

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Tipler                                                           |
//+------------------------------------------------------------------+
enum ENUM_RECT_STATE
  {
   RECT_IDLE             = 0, // Dikdortgen bekleniyor
   RECT_WAITING_FALSE    = 1, // Dikdortgen bulundu, sahte kirilim bekleniyor
   RECT_WAITING_BREAKOUT = 2  // Sahte kirilim goruldu, gercek kirilim bekleniyor
  };

//+------------------------------------------------------------------+
//| Girdiler                                                         |
//+------------------------------------------------------------------+
input group "1) Trend ve dikdortgen tespiti"
input ENUM_TIMEFRAMES InpTimeframe       = PERIOD_CURRENT;  // Islem zaman dilimi (0 = grafik TF)
input bool            InpUseTrendFilter  = true;            // Trend filtresi acik mi? (makale Adim 1)
input int             InpTrendFastEMA    = 20;              // Trend hizli EMA periyodu
input int             InpTrendSlowEMA    = 50;              // Trend yavas EMA periyodu
input int             InpLookbackBars    = 50;              // Dikdortgen tarama penceresi (mum)
input int             InpMinTouches      = 2;               // Her tarafta en az temas (makale: en az iki)
input double          InpTouchTolerancePct = 0.15;          // Temas toleransi (yuksekligin orani)
input int             InpMinDurationBars = 8;               // Temaslar arasi en az sure (mum)
input double          InpMinHeightATR    = 0.8;             // Min. dikdortgen yuksekligi (ATR kati)
input double          InpFlatnessPct     = 0.35;            // Yataylik: iki yari farki (yukseklik orani)
input int             InpMaxWaitBars     = 50;              // Dikdortgen gecerlilik suresi (mum, 0 = sinirsiz)

input group "2) Sahte kirilim ve giris/cikis (makale Adim 3-6)"
input bool   InpRequireFalseBreakout = true;  // Sahte kirilim sart olsun mu? (makale: yalniz yuksek olasilikli)
input int    InpFalseBufferPoints    = 10;    // Sahte kirilim fitil tamponu (point)
input double InpTPMultiplier         = 2.0;   // TP = yukseklik x bu carpan (makale: 2-3)
input int    InpSLBufferPoints       = 10;    // SL tamponu: direnc/destek disi (point)
input bool   InpCloseOnReenter       = false; // Kirilim sonrasi fiyat dikdortgene donerse kapat (opsiyonel)

input group "3) Pozisyon, risk ve emir"
input double InpLotSize          = 0.01;      // Sabit lot
input bool   InpUseRiskPercent   = false;     // true: SL mesafesine gore risk % ile lot hesapla
input double InpRiskPercent      = 1.0;       // Islem basina risk (%)
input ulong  InpMagicNumber      = 20261117;  // Magic Number
input int    InpDeviationPoints  = 20;        // Maksimum sapma (point)
input int    InpMaxSpreadPoints  = 0;         // Maksimum spread (point) - 0 = kapali
input int    InpMaxOpenPositions = 1;         // Ayni anda maks. pozisyon - 0 = sinirsiz
input bool   InpAllowLongs       = true;      // LONG acilsin (yukselis trendinde dikdortgen)
input bool   InpAllowShorts      = true;      // SHORT acilsin (dusus trendinde dikdortgen)
input double InpMaxSL_ATR        = 3.0;       // SL mesafesi ATR x bu degeri asarsa islem atlanir (0 = kapali)
input double InpMoneyTakeProfit  = 0.0;       // Para TP (hesap birimi, 0 = kapali)
input double InpMoneyStopLoss    = 0.0;       // Para SL (hesap birimi, 0 = kapali)
input int    InpMaxPositionMinutes = 0;       // Maks. pozisyon suresi (dakika, 0 = kapali)
input double InpMoveToBEAtHeightMult = 0.0;   // Fiyat yukseklik x bu kadar gidince SL'yi BE'ye cek (0 = kapali)

input group "4) Filtreler (otomatik koruma)"
input bool   InpUseTradingHours  = false;     // Islem saatleri filtresi acik mi?
input int    InpStartHour        = 0;         // Baslangic saati (sunucu saati, 0-23)
input int    InpEndHour          = 24;        // Bitis saati (0-24, 24 = gece yarisi)
input int    InpMaxTradesPerDay  = 0;         // Gunluk maks. islem (0 = sinirsiz)
input double InpMaxDailyLoss     = 0.0;       // Gunluk maks. zarar (hesap birimi, 0 = kapali)

input group "5) Gorsel ve gunluk"
input bool InpDrawRectangle = true;  // Dikdortgen cizgilerini ciz
input bool InpDrawArrows    = true;  // Sinyal oklari ciz
input bool InpShowPanel     = true;  // Grafikte bilgi paneli goster
input bool InpDeleteOnExit  = true;  // EA kapanirken kendi nesnelerini sil
input bool InpLogSignals    = false; // Her yeni mumda sinyal/seviye logla

//+------------------------------------------------------------------+
//| Global durum                                                     |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES g_tf              = PERIOD_CURRENT;
int             g_ema_fast_handle = INVALID_HANDLE;
int             g_ema_slow_handle = INVALID_HANDLE;
int             g_atr_handle      = INVALID_HANDLE;
datetime        g_last_bar_time   = 0;

ENUM_RECT_STATE g_rect_state      = RECT_IDLE;
int             g_rect_side       = 0;      // +1 LONG kurulumu, -1 SHORT kurulumu, 0 yok
double          g_rect_R          = 0.0;    // Direnc (ust cizgi)
double          g_rect_S          = 0.0;    // Destek (alt cizgi)
double          g_rect_height     = 0.0;    // R - S
datetime        g_rect_start_time = 0;      // Olusum penceresinin en eski mumu
datetime        g_rect_found_time = 0;      // Dikdortgenin bulundugu mum
int             g_rect_wait_bars  = 0;      // Bulundugundan beri gecen mum
int             g_rect_touches_R  = 0;
int             g_rect_touches_S  = 0;
bool            g_rect_false_seen = false;
int             g_current_trend   = 0;      // +1 yukselis, -1 dusus, 0 belirsiz

int             g_signal_count     = 0;
int             g_skip_count       = 0;
int             g_trades_today     = 0;
datetime        g_trades_day       = 0;
double          g_day_start_equity = 0.0;
string          g_last_action      = "Baslatiliyor";
string          g_object_prefix    = "";

//+------------------------------------------------------------------+
//| Temel yardimcilar                                                |
//+------------------------------------------------------------------+
string SideName(const int side)
  {
   if(side > 0)
      return "LONG";
   if(side < 0)
      return "SHORT";
   return "BEKLENIYOR";
  }

string TrendName(const int trend)
  {
   if(trend > 0)
      return "YUKSELIS";
   if(trend < 0)
      return "DUSUS";
   return "BELIRSIZ";
  }

string StateName()
  {
   switch(g_rect_state)
     {
      case RECT_WAITING_FALSE:    return "SAHTE KIRILIM BEKLENIYOR";
      case RECT_WAITING_BREAKOUT: return "GERCEK KIRILIM BEKLENIYOR";
      default:                    return "IDLE (dikdortgen bekleniyor)";
     }
  }

double TickSize()
  {
   double size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(size <= 0.0)
      size = _Point;
   return size;
  }

double NormalizePriceToTick(const double price, const int round_direction)
  {
   double tick = TickSize();
   if(price <= 0.0 || tick <= 0.0)
      return NormalizeDouble(price, _Digits);
   double units = price / tick;
   if(round_direction > 0)
      units = MathCeil(units - 1.0e-10);
   else if(round_direction < 0)
      units = MathFloor(units + 1.0e-10);
   else
      units = MathRound(units);
   return NormalizeDouble(units * tick, _Digits);
  }

double NormalizeVolume(const double volume)
  {
   double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(min_vol <= 0.0 || max_vol <= 0.0 || step <= 0.0)
      return 0.0;
   double vol = volume;
   vol = MathFloor(vol / step + 1.0e-10) * step;
   vol = MathMax(min_vol, MathMin(max_vol, vol));
   return NormalizeDouble(vol, 2);
  }

ENUM_TIMEFRAMES WorkingTimeframe()
  {
   if(InpTimeframe == PERIOD_CURRENT)
      return _Period;
   return InpTimeframe;
  }

//+------------------------------------------------------------------+
//| Pozisyon yardimcilari                                            |
//+------------------------------------------------------------------+
bool SelectOurPosition(const ulong ticket)
  {
   if(ticket == 0)
      return false;
   if(!PositionSelectByTicket(ticket))
      return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
      return false;
   return true;
  }

int SideFromPositionType(const long type)
  {
   if(type == POSITION_TYPE_BUY)
      return 1;
   if(type == POSITION_TYPE_SELL)
      return -1;
   return 0;
  }

int CountOurPositions(const int side)
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      if(side == 0 || SideFromPositionType(PositionGetInteger(POSITION_TYPE)) == side)
         count++;
     }
   return count;
  }

bool TradeRetcodeOK(const bool sent)
  {
   if(!sent)
      return false;
   uint code = trade.ResultRetcode();
   return (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_PLACED ||
           code == TRADE_RETCODE_DONE_PARTIAL);
  }

bool CloseOurPosition(const ulong ticket, const string reason)
  {
   if(!SelectOurPosition(ticket))
      return false;
   long   type   = PositionGetInteger(POSITION_TYPE);
   double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   bool   sent   = false;
   if(type == POSITION_TYPE_BUY)
      sent = trade.PositionClose(ticket, InpDeviationPoints);
   else if(type == POSITION_TYPE_SELL)
      sent = trade.PositionClose(ticket, InpDeviationPoints);
   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Kapatma basarisiz: ticket=%I64u sebep=%s retcode=%u (%s)",
                  ticket, reason, trade.ResultRetcode(),
                  trade.ResultRetcodeDescription());
      return false;
     }
   PrintFormat("KAPATILDI: ticket=%I64u sebep=%s kar=%.2f",
               ticket, reason, profit);
   g_last_action = StringFormat("Pozisyon kapatildi (%s)", reason);
   return true;
  }

//+------------------------------------------------------------------+
//| Gosterge okuma ve trend                                          |
//+------------------------------------------------------------------+
bool GetEMA(const int handle, const int shift, double &value)
  {
   if(handle == INVALID_HANDLE)
      return false;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) != 1)
      return false;
   value = buf[0];
   return true;
  }

bool GetATR(const int shift, double &value)
  {
   if(g_atr_handle == INVALID_HANDLE)
      return false;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_atr_handle, 0, shift, 1, buf) != 1)
      return false;
   value = buf[0];
   return true;
  }

// Makale Adim 1: hakim trend. EMA fast/slow iliskisi + kapanis konumu.
int CalcTrend(const double close1)
  {
   double fast = 0.0, slow = 0.0;
   if(!GetEMA(g_ema_fast_handle, 1, fast) || !GetEMA(g_ema_slow_handle, 1, slow))
      return 0;
   if(fast > slow && close1 > slow)
      return 1;
   if(fast < slow && close1 < slow)
      return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| Filtreler                                                        |
//+------------------------------------------------------------------+
bool WithinTradingHours()
  {
   if(!InpUseTradingHours)
      return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   if(InpStartHour <= InpEndHour)
      return (hour >= InpStartHour && hour < InpEndHour);
   return (hour >= InpStartHour || hour < InpEndHour); // gece asimi
  }

void RefreshDailyCounters()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime day_start = StructToTime(dt);
   if(g_trades_day != day_start)
     {
      g_trades_day       = day_start;
      g_trades_today     = 0;
      g_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
     }
  }

bool DailyLimitsOK()
  {
   RefreshDailyCounters();
   if(InpMaxTradesPerDay > 0 && g_trades_today >= InpMaxTradesPerDay)
      return false;
   if(InpMaxDailyLoss > 0.0)
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(g_day_start_equity - equity >= InpMaxDailyLoss)
         return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Dikdortgen nesneleri (grafik cizimi)                             |
//+------------------------------------------------------------------+
string RectLineName(const string suffix)
  {
   return g_object_prefix + "RECT_" + suffix;
  }

void DeleteRectangleObjects()
  {
   ObjectDelete(0, RectLineName("R"));
   ObjectDelete(0, RectLineName("S"));
   ObjectDelete(0, RectLineName("LABEL"));
  }

void DrawRectangleObjects(const datetime end_time)
  {
   if(!InpDrawRectangle || g_rect_state == RECT_IDLE || g_rect_R <= 0.0 || g_rect_S <= 0.0)
      return;
   string name_r = RectLineName("R");
   string name_s = RectLineName("S");
   string name_l = RectLineName("LABEL");
   if(ObjectFind(0, name_r) < 0)
     {
      ObjectCreate(0, name_r, OBJ_TREND, 0, g_rect_start_time, g_rect_R, end_time, g_rect_R);
      ObjectSetInteger(0, name_r, OBJPROP_COLOR, clrTomato);
      ObjectSetInteger(0, name_r, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name_r, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, name_r, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name_r, OBJPROP_HIDDEN, true);
     }
   else
     {
      ObjectMove(0, name_r, 0, g_rect_start_time, g_rect_R);
      ObjectMove(0, name_r, 1, end_time, g_rect_R);
     }
   if(ObjectFind(0, name_s) < 0)
     {
      ObjectCreate(0, name_s, OBJ_TREND, 0, g_rect_start_time, g_rect_S, end_time, g_rect_S);
      ObjectSetInteger(0, name_s, OBJPROP_COLOR, clrLimeGreen);
      ObjectSetInteger(0, name_s, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name_s, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, name_s, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name_s, OBJPROP_HIDDEN, true);
     }
   else
     {
      ObjectMove(0, name_s, 0, g_rect_start_time, g_rect_S);
      ObjectMove(0, name_s, 1, end_time, g_rect_S);
     }
   if(ObjectFind(0, name_l) < 0)
     {
      ObjectCreate(0, name_l, OBJ_TEXT, 0, end_time, g_rect_R);
      ObjectSetInteger(0, name_l, OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, name_l, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name_l, OBJPROP_HIDDEN, true);
     }
   ObjectMove(0, name_l, 0, end_time, g_rect_R);
   ObjectSetString(0, name_l, OBJPROP_TEXT,
                   StringFormat("RECT %s R=%.*f S=%.*f H=%.*f",
                                SideName(g_rect_side), _Digits, g_rect_R,
                                _Digits, g_rect_S, _Digits, g_rect_height));
  }

//+------------------------------------------------------------------+
//| Dikdortgen kurulum yonetimi                                      |
//+------------------------------------------------------------------+
void ResetRectangle(const string reason)
  {
   if(g_rect_state != RECT_IDLE && reason != "")
      PrintFormat("Dikdortgen iptal/sifirlandi: yon=%s sebep=%s",
                  SideName(g_rect_side), reason);
   g_rect_state      = RECT_IDLE;
   g_rect_side       = 0;
   g_rect_R          = 0.0;
   g_rect_S          = 0.0;
   g_rect_height     = 0.0;
   g_rect_start_time = 0;
   g_rect_found_time = 0;
   g_rect_wait_bars  = 0;
   g_rect_touches_R  = 0;
   g_rect_touches_S  = 0;
   g_rect_false_seen = false;
   DeleteRectangleObjects();
  }

void StoreRectangle(const int side, const double r, const double s,
                    const int touches_r, const int touches_s,
                    const datetime start_time, const datetime found_time)
  {
   g_rect_state      = (InpRequireFalseBreakout ? RECT_WAITING_FALSE : RECT_WAITING_BREAKOUT);
   g_rect_side       = side;
   g_rect_R          = r;
   g_rect_S          = s;
   g_rect_height     = r - s;
   g_rect_start_time = start_time;
   g_rect_found_time = found_time;
   g_rect_wait_bars  = 0;
   g_rect_touches_R  = touches_r;
   g_rect_touches_S  = touches_s;
   g_rect_false_seen = false;
   g_last_action     = StringFormat("Dikdortgen bulundu (%s) R=%.*f S=%.*f",
                                    SideName(side), _Digits, r, _Digits, s);
   PrintFormat("DIKDORTGEN BULUNDU: yon=%s R=%.*f S=%.*f yukseklik=%.*f temas R/S=%d/%d mum=%s",
               SideName(side), _Digits, r, _Digits, s, _Digits, r - s,
               touches_r, touches_s, TimeToString(found_time));
   DrawRectangleObjects(found_time);
  }

//+------------------------------------------------------------------+
//| Dikdortgen aday tespiti (makale Adim 2)                          |
//| Son InpLookbackBars mumda: en yuksek tepe / en dusuk dip, her    |
//| tarafta temas sayisi, temas suresi ve yataylik kontrolu.         |
//+------------------------------------------------------------------+
bool FindRectangleCandidate(const MqlRates &rates[], const double atr1,
                            double &out_r, double &out_s,
                            int &out_touches_r, int &out_touches_s,
                            datetime &out_start_time)
  {
   int n = InpLookbackBars;
   if(ArraySize(rates) <= n + 1 || n < 10)
      return false;

   double r = rates[1].high, s = rates[1].low;
   for(int i = 1; i <= n; i++)
     {
      r = MathMax(r, rates[i].high);
      s = MathMin(s, rates[i].low);
     }
   double height = r - s;
   if(height <= 0.0)
      return false;
   if(atr1 > 0.0 && height < InpMinHeightATR * atr1)
      return false;

   double tol = height * InpTouchTolerancePct;
   if(tol <= 0.0)
      return false;

   int touches_r = 0, touches_s = 0;
   int first_touch_idx = n + 1, last_touch_idx = 0;
   for(int i = 1; i <= n; i++)
     {
      bool touch_r = (rates[i].high >= r - tol);
      bool touch_s = (rates[i].low <= s + tol);
      if(touch_r)
         touches_r++;
      if(touch_s)
         touches_s++;
      if(touch_r || touch_s)
        {
         first_touch_idx = MathMin(first_touch_idx, i);
         last_touch_idx  = MathMax(last_touch_idx, i);
        }
     }
   if(touches_r < InpMinTouches || touches_s < InpMinTouches)
      return false;
   if(last_touch_idx - first_touch_idx < InpMinDurationBars)
      return false;

   // Yataylik: pencerenin iki yarisi ayni bantta mi? (trend kanali eleme)
   int half = n / 2;
   double high_recent = rates[1].high, low_recent = rates[1].low;
   double high_old = rates[half + 1].high, low_old = rates[half + 1].low;
   for(int i = 1; i <= half; i++)
     {
      high_recent = MathMax(high_recent, rates[i].high);
      low_recent  = MathMin(low_recent, rates[i].low);
     }
   for(int i = half + 1; i <= n; i++)
     {
      high_old = MathMax(high_old, rates[i].high);
      low_old  = MathMin(low_old, rates[i].low);
     }
   if(MathAbs(high_recent - high_old) > height * InpFlatnessPct)
      return false;
   if(MathAbs(low_recent - low_old) > height * InpFlatnessPct)
      return false;

   out_r = r;
   out_s = s;
   out_touches_r = touches_r;
   out_touches_s = touches_s;
   out_start_time = rates[n].time;
   return true;
  }

//+------------------------------------------------------------------+
//| Lot hesabi (sabit veya risk % )                                  |
//+------------------------------------------------------------------+
double CalcLot(const int side, const double entry, const double sl)
  {
   if(!InpUseRiskPercent)
      return NormalizeVolume(InpLotSize);
   if(sl <= 0.0 || entry <= 0.0)
      return NormalizeVolume(InpLotSize);
   double sl_distance = MathAbs(entry - sl);
   if(sl_distance <= 0.0)
      return 0.0;
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0.0 || tick_value <= 0.0)
      return NormalizeVolume(InpLotSize);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_money = equity * InpRiskPercent / 100.0;
   double loss_per_lot = (sl_distance / tick_size) * tick_value;
   if(loss_per_lot <= 0.0)
      return 0.0;
   return NormalizeVolume(risk_money / loss_per_lot);
  }

//+------------------------------------------------------------------+
//| Emir acma (makale Adim 4-6)                                     |
//+------------------------------------------------------------------+
void DrawSignalArrow(const datetime bar_time, const double high,
                     const double low, const int side)
  {
   if(!InpDrawArrows)
      return;
   string name = g_object_prefix + IntegerToString((long)bar_time) +
                 (side > 0 ? "_B" : "_S");
   if(ObjectFind(0, name) >= 0)
      return;
   double offset = MathMax((high - low) * 0.25, _Point * 20.0);
   if(side > 0)
     {
      if(!ObjectCreate(0, name, OBJ_ARROW_BUY, 0, bar_time, low - offset))
         return;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrLimeGreen);
     }
   else
     {
      if(!ObjectCreate(0, name, OBJ_ARROW_SELL, 0, bar_time, high + offset))
         return;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrTomato);
     }
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

bool OpenTrade(const int side, const double sl, const double tp,
               const string signal_text, const datetime signal_time,
               const double sig_high, const double sig_low)
  {
   if(side == 0)
      return false;
   if(side > 0 && !InpAllowLongs)
     {
      g_last_action = "LONG giris ayarlardan kapali";
      return false;
     }
   if(side < 0 && !InpAllowShorts)
     {
      g_last_action = "SHORT giris ayarlardan kapali";
      return false;
     }
   if(InpMaxOpenPositions > 0 && CountOurPositions(0) >= InpMaxOpenPositions)
     {
      g_skip_count++;
      g_last_action = "Maksimum pozisyon sayisina ulasildi";
      return false;
     }
   if(!WithinTradingHours())
     {
      g_skip_count++;
      g_last_action = "Islem saatleri disinda";
      return false;
     }
   if(!DailyLimitsOK())
     {
      g_skip_count++;
      g_last_action = "Gunluk limit doldu";
      return false;
     }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
      return false;

   double spread_points = (tick.ask - tick.bid) / _Point;
   if(InpMaxSpreadPoints > 0 && spread_points > InpMaxSpreadPoints)
     {
      g_skip_count++;
      g_last_action = StringFormat("Spread yuksek: %.1f point", spread_points);
      return false;
     }

   double entry = (side > 0 ? tick.ask : tick.bid);

   // Broker minimum mesafe kontrolu
   long stops_level  = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_distance = MathMax((double)stops_level, (double)freeze_level) * _Point;
   if(sl > 0.0 && MathAbs(entry - sl) < min_distance + TickSize())
     {
      g_skip_count++;
      g_last_action = "SL broker minimum mesafesinden kucuk, islem atlandi";
      PrintFormat("ATLANDI: SL mesafesi cok kucuk | yon=%s entry=%.5f sl=%.5f",
                  SideName(side), entry, sl);
      return false;
     }
   if(tp > 0.0 && MathAbs(tp - entry) < min_distance + TickSize())
     {
      g_skip_count++;
      g_last_action = "TP broker minimum mesafesinden kucuk, islem atlandi";
      return false;
     }

   // SL mesafesi ATR filtresi
   if(sl > 0.0 && InpMaxSL_ATR > 0.0)
     {
      double atr = 0.0;
      if(GetATR(1, atr) && atr > 0.0 && MathAbs(entry - sl) > InpMaxSL_ATR * atr)
        {
         g_skip_count++;
         g_last_action = StringFormat("SL mesafesi ATR filtresi: %.1f x ATR", MathAbs(entry - sl) / atr);
         PrintFormat("ATLANDI: SL cok genis | yon=%s mesafe=%.5f ATR=%.5f",
                     SideName(side), MathAbs(entry - sl), atr);
         return false;
        }
     }

   double volume = CalcLot(side, entry, sl);
   if(volume <= 0.0)
     {
      g_last_action = "Lot hacmi broker sinirlarina uymuyor";
      return false;
     }

   string comment = (side > 0 ? "RECT BUY" : "RECT SELL");
   bool sent = false;
   if(side > 0)
      sent = trade.Buy(volume, _Symbol, 0.0, sl, tp, comment);
   else
      sent = trade.Sell(volume, _Symbol, 0.0, sl, tp, comment);

   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Giris basarisiz: %s | yon=%s lot=%.8f retcode=%u (%s)",
                  signal_text, SideName(side), volume,
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
      g_last_action = "Emir broker tarafindan reddedildi";
      return false;
     }

   g_signal_count++;
   RefreshDailyCounters();
   g_trades_today++;
   DrawSignalArrow(signal_time, sig_high, sig_low, side);
   PrintFormat("GIRIS: %s | yon=%s | sinyal mumu=%s | lot=%.8f | fiyat=%.*f | SL=%.*f | TP=%.*f",
               signal_text, SideName(side), TimeToString(signal_time),
               volume, _Digits, entry, _Digits, sl, _Digits, tp);
   g_last_action = StringFormat("%s islem acildi (%s)", SideName(side), signal_text);
   // Dikdortgen cizgileri pozisyon kapanana kadar grafikte kalir
   return true;
  }

//+------------------------------------------------------------------+
//| Tick duzeyinde cikislar (para / sure / BE / reenter)             |
//+------------------------------------------------------------------+
void CheckTickExits()
  {
   if(CountOurPositions(0) == 0)
      return;
   datetime now = TimeCurrent();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int    side   = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(InpMoneyTakeProfit > 0.0 && profit >= InpMoneyTakeProfit)
        {
         CloseOurPosition(ticket, StringFormat("para TP (%.2f)", profit));
         continue;
        }
      if(InpMoneyStopLoss > 0.0 && profit <= -InpMoneyStopLoss)
        {
         CloseOurPosition(ticket, StringFormat("para SL (%.2f)", profit));
         continue;
        }
      if(InpMaxPositionMinutes > 0)
        {
         datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
         long seconds_open = (long)(now - open_time);
         if(seconds_open >= (long)InpMaxPositionMinutes * 60)
           {
            CloseOurPosition(ticket, StringFormat("sure siniri (%d dk)", InpMaxPositionMinutes));
            continue;
           }
        }
      // Opsiyonel: fiyat yukseklik kati gidince SL'yi BE'ye cek
      if(InpMoveToBEAtHeightMult > 0.0 && g_rect_height > 0.0 && side != 0)
        {
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur_sl     = PositionGetDouble(POSITION_SL);
         double cur_price  = (side > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                       : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
         double moved      = side * (cur_price - open_price);
         bool   hit        = (moved >= InpMoveToBEAtHeightMult * g_rect_height);
         bool   need_move  = (side > 0 && (cur_sl <= 0.0 || cur_sl < open_price)) ||
                             (side < 0 && (cur_sl <= 0.0 || cur_sl > open_price));
         if(hit && need_move)
           {
            double be_sl  = NormalizePriceToTick(open_price, (side > 0 ? 1 : -1));
            double cur_tp = PositionGetDouble(POSITION_TP);
            if(trade.PositionModify(ticket, be_sl, cur_tp))
               PrintFormat("SL BE'ye cekildi: ticket=%I64u", ticket);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Kapanmis mumda reenter kontrolu (opsiyonel basarisiz kirilim)    |
//+------------------------------------------------------------------+
void CheckReenterExit(const MqlRates &rates[])
  {
   if(!InpCloseOnReenter || g_rect_state == RECT_IDLE)
      return;
   if(CountOurPositions(0) == 0 || ArraySize(rates) < 2)
      return;
   double close1 = rates[1].close;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
      // SHORT kirilimi sonrasi kapanis tekrar dikdortgen icine donerse
      if(side < 0 && close1 > g_rect_S && close1 < g_rect_R)
         CloseOurPosition(ticket, "basarisiz kirilim: fiyat dikdortgene dondu");
      // LONG kirilimi sonrasi kapanis tekrar dikdortgen icine donerse
      if(side > 0 && close1 < g_rect_R && close1 > g_rect_S)
         CloseOurPosition(ticket, "basarisiz kirilim: fiyat dikdortgene dondu");
     }
  }

//+------------------------------------------------------------------+
//| Dikdortgen isleme (makale 6 adim)                                |
//+------------------------------------------------------------------+
void ProcessRectangleMode(const MqlRates &rates[], const double &atr[])
  {
   if(ArraySize(rates) < 3)
      return;
   double atr1 = (ArraySize(atr) > 1 ? atr[1] : 0.0);
   double close1 = rates[1].close;
   double high1  = rates[1].high;
   double low1   = rates[1].low;

   g_current_trend = CalcTrend(close1);

   // --- IDLE: Adim 1-2 trend + dikdortgen tespiti ---
   if(g_rect_state == RECT_IDLE)
     {
      double r = 0.0, s = 0.0;
      int touches_r = 0, touches_s = 0;
      datetime start_time = 0;
      if(!FindRectangleCandidate(rates, atr1, r, s, touches_r, touches_s, start_time))
         return;

      int side = 0;
      if(InpUseTrendFilter)
        {
         // Adim 1: yukselis trendi -> LONG kurulumu, dusus trendi -> SHORT
         if(g_current_trend > 0 && InpAllowLongs)
            side = 1;
         else if(g_current_trend < 0 && InpAllowShorts)
            side = -1;
        }
      else
        {
         // Trend filtresi kapali: her iki yon da aday (reversal dahil)
         // Yon, sahte kirilim yonune gore belirleneceginden burada
         // trend yonunu tercih et; belirsizse LONG dene.
         if(g_current_trend != 0)
            side = g_current_trend;
         else if(InpAllowLongs)
            side = 1;
         else if(InpAllowShorts)
            side = -1;
        }
      if(side == 0)
        {
         if(InpLogSignals)
            PrintFormat("RECT[%s] dikdortgen aday var ama trend yonune uygun degil (trend=%s)",
                        TimeToString(rates[1].time, TIME_DATE | TIME_MINUTES),
                        TrendName(g_current_trend));
         return;
        }
      StoreRectangle(side, r, s, touches_r, touches_s, start_time, rates[1].time);
      return;
     }

   // --- Bekleme durumlari: Adim 3-4 ---
   g_rect_wait_bars++;
   DrawRectangleObjects(rates[1].time);

   if(InpMaxWaitBars > 0 && g_rect_wait_bars > InpMaxWaitBars)
     {
      ResetRectangle("dikdortgen gecerlilik suresi doldu");
      return;
     }

   int side = g_rect_side;
   double buffer = InpFalseBufferPoints * _Point;

   // Trend hala ayni yonde mi? (Adim 1 gecerliligi)
   if(InpUseTrendFilter && g_current_trend != 0 && g_current_trend != side)
     {
      PrintFormat("Trend degisti (%s), dikdortgen kurulumu iptal.", TrendName(g_current_trend));
      ResetRectangle("trend degisti");
      return;
     }

   if(g_rect_state == RECT_WAITING_FALSE)
     {
      // Adim 3: sahte kirilim - fitil disari, kapanis iceri
      bool false_break = false;
      if(side < 0)
        {
         // SHORT kurulumu: direnc uzerinde sahte kirilim
         false_break = (high1 > g_rect_R + buffer && close1 < g_rect_R && low1 >= g_rect_S - g_rect_height * InpTouchTolerancePct);
        }
      else if(side > 0)
        {
         // LONG kurulumu: destek altinda sahte kirilim
         false_break = (low1 < g_rect_S - buffer && close1 > g_rect_S && high1 <= g_rect_R + g_rect_height * InpTouchTolerancePct);
        }
      if(false_break)
        {
         g_rect_state      = RECT_WAITING_BREAKOUT;
         g_rect_false_seen = true;
         g_rect_wait_bars  = 0;
         PrintFormat("Adim 3 (%s): sahte kirilim goruldu (mum=%s). Gercek kirilim bekleniyor.",
                     SideName(side), TimeToString(rates[1].time));
         g_last_action = StringFormat("Sahte kirilim goruldu (%s), kirilim bekleniyor", SideName(side));
         return;
        }

      // Sahte kirilim olmadan gercek kirilim gelirse: makale filtresi
      if(InpRequireFalseBreakout)
        {
         if(side < 0 && close1 < g_rect_S)
           {
            Print("Sahte kirilim olmadan destek kirildi; makale filtresi geregi islem YOK.");
            ResetRectangle("sahte kirilim olmadan kirilim");
            return;
           }
         if(side > 0 && close1 > g_rect_R)
           {
            Print("Sahte kirilim olmadan direnc kirildi; makale filtresi geregi islem YOK.");
            ResetRectangle("sahte kirilim olmadan kirilim");
            return;
           }
        }
      else
        {
         // Sahte kirilim sarti kapaliysa dogrudan kirilimla girise gec
         g_rect_state = RECT_WAITING_BREAKOUT;
         g_rect_wait_bars = 0;
        }
      return;
     }

   if(g_rect_state == RECT_WAITING_BREAKOUT)
     {
      // Adim 4: kirilim mumu kapanisiyle giris
      bool breakout = false;
      if(side < 0 && close1 < g_rect_S)
         breakout = true;
      if(side > 0 && close1 > g_rect_R)
         breakout = true;

      if(breakout)
        {
         // Adim 6: SL direnc/destek disi tampon
         // Adim 5: TP = yukseklik x carpan (giris fiyatindan)
         double sl_buffer = InpSLBufferPoints * _Point;
         double sl = 0.0;
         if(side < 0)
            sl = NormalizePriceToTick(g_rect_R + sl_buffer, 1);
         else
            sl = NormalizePriceToTick(g_rect_S - sl_buffer, -1);

         // TP icin giris fiyati tahmini: kirilim kapanisi
         double est_entry = close1;
         double tp = 0.0;
         if(side < 0)
            tp = NormalizePriceToTick(est_entry - InpTPMultiplier * g_rect_height, -1);
         else
            tp = NormalizePriceToTick(est_entry + InpTPMultiplier * g_rect_height, 1);

         string text = StringFormat("Adim 4 kirilim kapanisi -> %s (R=%.*f S=%.*f H=%.*f x%.1f)",
                                    SideName(side), _Digits, g_rect_R, _Digits, g_rect_S,
                                    _Digits, g_rect_height, InpTPMultiplier);
         bool opened = OpenTrade(side, sl, tp, text, rates[1].time, high1, low1);
         if(opened)
           {
            // Cizgiler pozisyon kapanana kadar kalir; durum IDLE'ye doner
            // ancak cizgiler CheckReenterExit / panel icin korunur.
            // Yeni kurulum, pozisyon varken baslatilmaz (ProcessClosedBar).
            g_rect_state = RECT_IDLE;
            g_rect_side  = 0;
            g_rect_wait_bars = 0;
            g_rect_false_seen = false;
           }
         else
           {
            // Emir acilamazsa (spread/limit) kurulumu sifirla
            ResetRectangle("emir acilamadi");
           }
         return;
        }

      // Ters yonlu guclu kirilim kurulumu gecersiz kilar
      if(side < 0 && close1 > g_rect_R + buffer)
        {
         ResetRectangle("ters yonlu kirilim (direnc uzeri kapanis)");
         return;
        }
      if(side > 0 && close1 < g_rect_S - buffer)
        {
         ResetRectangle("ters yonlu kirilim (destek alti kapanis)");
         return;
        }
     }
  }

//+------------------------------------------------------------------+
//| Bilgi paneli                                                     |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   if(!InpShowPanel)
     {
      Comment("");
      return;
     }
   double atr1 = 0.0;
   GetATR(1, atr1);

   string rect_text;
   if(g_rect_state == RECT_IDLE && g_rect_R <= 0.0)
      rect_text = "IDLE";
   else
      rect_text = StringFormat("%s | yon=%s | R=%s S=%s H=%s | temas=%d/%d | bekleme=%d mum",
                               StateName(), SideName(g_rect_side),
                               DoubleToString(g_rect_R, _Digits),
                               DoubleToString(g_rect_S, _Digits),
                               DoubleToString(g_rect_height, _Digits),
                               g_rect_touches_R, g_rect_touches_S, g_rect_wait_bars);

   Comment("Rectangle Pattern ROBOT v1.00\n",
           "Sembol: ", _Symbol, " | TF: ", EnumToString(g_tf),
           " | spread: ", DoubleToString((SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                                          SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point, 0),
           " point\n",
           "Trend: ", TrendName(g_current_trend),
           " (EMA ", IntegerToString(InpTrendFastEMA), "/", IntegerToString(InpTrendSlowEMA), ")",
           " | ATR=", DoubleToString(atr1, _Digits), "\n",
           "Dikdortgen: ", rect_text, "\n",
           "Sahte kirilim sarti: ", (InpRequireFalseBreakout ? "ACIK" : "KAPALI"),
           " | TP carpan: x", DoubleToString(InpTPMultiplier, 1), "\n",
           "Acik pozisyon BUY/SELL: ", IntegerToString(CountOurPositions(1)), " / ",
           IntegerToString(CountOurPositions(-1)),
           " | sinyal: ", IntegerToString(g_signal_count),
           " | atlanan: ", IntegerToString(g_skip_count),
           " | bugunku islem: ", IntegerToString(g_trades_today), "\n",
           "Durum: ", g_last_action);
  }

//+------------------------------------------------------------------+
//| Kapanmis mum isleme                                              |
//+------------------------------------------------------------------+
void ProcessClosedBar()
  {
   int needed = (int)MathMax(100, MathMax(InpLookbackBars + 50,
                                           InpTrendSlowEMA * 3 + 20));
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, g_tf, 0, needed, rates);
   if(copied < 10)
     {
      g_last_action = StringFormat("Yetersiz mum verisi: %d", copied);
      return;
     }

   double atr[];
   ArraySetAsSeries(atr, true);
   if(g_atr_handle != INVALID_HANDLE)
      CopyBuffer(g_atr_handle, 0, 0, needed, atr);

   if(ArraySize(atr) < 3)
     {
      g_last_action = "Gosterge verisi henuz hazir degil";
      return;
     }

   if(InpLogSignals)
      PrintFormat("RECT[%s] trend=%s durum=%s R=%.*f S=%.*f",
                  TimeToString(rates[1].time, TIME_DATE | TIME_MINUTES),
                  TrendName(g_current_trend), StateName(),
                  _Digits, g_rect_R, _Digits, g_rect_S);

   // 1) Opsiyonel basarisiz kirilim cikisi
   CheckReenterExit(rates);

   // 2) Pozisyon aciksa yeni kurulum baslatma (tek pozisyon disiplini)
   if(CountOurPositions(0) > 0)
     {
      if(g_rect_state != RECT_IDLE)
        {
         // Pozisyon acildiktan sonra cizgiler korunur; bekleme durumu temizlenir
         g_rect_state = RECT_IDLE;
         g_rect_side  = 0;
         g_rect_wait_bars = 0;
        }
      g_last_action = "Pozisyon acik, yeni sinyal bekleniyor";
      return;
     }

   // 3) Dikdortgen isleme
   ProcessRectangleMode(rates, atr);
  }

void CheckNewBar()
  {
   datetime current_bar_time = iTime(_Symbol, g_tf, 0);
   if(current_bar_time <= 0)
      return;
   if(g_last_bar_time == 0)
     {
      // EA acildiginda gecmise donuk islem acilmaz
      g_last_bar_time = current_bar_time;
      return;
     }
   if(current_bar_time == g_last_bar_time)
      return;
   g_last_bar_time = current_bar_time;
   ProcessClosedBar();
  }

//+------------------------------------------------------------------+
//| Standart olaylar                                                 |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_tf = WorkingTimeframe();
   if(PeriodSeconds(g_tf) <= 0)
     {
      Print("EA baslatilamadi: gecersiz zaman dilimi.");
      return INIT_FAILED;
     }
   if(InpTrendFastEMA < 2 || InpTrendSlowEMA < 3 || InpTrendFastEMA >= InpTrendSlowEMA)
     {
      Print("Hatali girdiler: 2 <= hizli EMA < yavas EMA olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLookbackBars < 10 || InpMinTouches < 2 || InpMinTouches > 5 ||
      InpMinDurationBars < 1 || InpMaxWaitBars < 0)
     {
      Print("Hatali girdiler: bakis >= 10, temas 2-5, sure >= 1 olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpTouchTolerancePct <= 0.0 || InpTouchTolerancePct > 0.5 ||
      InpFlatnessPct <= 0.0 || InpFlatnessPct > 1.0 ||
      InpMinHeightATR < 0.0 || !MathIsValidNumber(InpTouchTolerancePct) ||
      !MathIsValidNumber(InpFlatnessPct) || !MathIsValidNumber(InpMinHeightATR))
     {
      Print("Hatali girdiler: tolerans/yataylik/yukseklik oranlari gecersiz.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpTPMultiplier < 1.0 || InpTPMultiplier > 5.0 || !MathIsValidNumber(InpTPMultiplier))
     {
      Print("Hatali girdiler: TP carpani 1.0-5.0 arasinda olmali (makale: 2-3).");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLotSize <= 0.0 || !MathIsValidNumber(InpLotSize) ||
      InpRiskPercent <= 0.0 || !MathIsValidNumber(InpRiskPercent))
     {
      Print("Hatali girdiler: lot ve risk % pozitif olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMaxOpenPositions < 0 || InpDeviationPoints < 0 || InpMaxSpreadPoints < 0 ||
      InpSLBufferPoints < 0 || InpFalseBufferPoints < 0 || InpMaxPositionMinutes < 0 ||
      InpMaxTradesPerDay < 0)
     {
      Print("Hatali girdiler: sayisal ayarlar negatif olamaz.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMoneyTakeProfit < 0.0 || InpMoneyStopLoss < 0.0 || InpMaxDailyLoss < 0.0 ||
      InpMaxSL_ATR < 0.0 || InpMoveToBEAtHeightMult < 0.0)
     {
      Print("Hatali girdiler: para/ATR esikleri negatif olamaz (0 = kapali).");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpStartHour < 0 || InpStartHour > 23 || InpEndHour < 0 || InpEndHour > 24)
     {
      Print("Hatali girdiler: islem saatleri 0-23 / 0-24 arasinda olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!InpAllowLongs && !InpAllowShorts)
     {
      Print("Hatali girdiler: en az bir yon (LONG veya SHORT) acik olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpTPMultiplier < 2.0 || InpTPMultiplier > 3.0)
      Print("BILGI: TP carpani makalenin 2-3 araligi disinda; tester ile dogrulayin.");

   if(!SymbolSelect(_Symbol, true))
     {
      Print("EA baslatilamadi: sembol secilemiyor.");
      return INIT_FAILED;
     }

   g_ema_fast_handle = iMA(_Symbol, g_tf, InpTrendFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_ema_slow_handle = iMA(_Symbol, g_tf, InpTrendSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_atr_handle      = iATR(_Symbol, g_tf, 14);
   if(g_ema_fast_handle == INVALID_HANDLE || g_ema_slow_handle == INVALID_HANDLE ||
      g_atr_handle == INVALID_HANDLE)
     {
      Print("EA baslatilamadi: EMA/ATR gosterge handle olusturulamadi.");
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_object_prefix = StringFormat("RECT_%I64u_%s_%s_",
                                  InpMagicNumber, _Symbol, EnumToString(g_tf));
   g_last_bar_time = iTime(_Symbol, g_tf, 0);
   RefreshDailyCounters();
   ResetRectangle("");

   EventSetTimer(1);

   PrintFormat("RECTANGLE ROBOT hazir: %s TF=%s | trend EMA %d/%d filtre=%s | bakis=%d temas>=%d | TP x%.1f | lot=%.2f magic=%I64u",
               _Symbol, EnumToString(g_tf), InpTrendFastEMA, InpTrendSlowEMA,
               (InpUseTrendFilter ? "ACIK" : "KAPALI"), InpLookbackBars,
               InpMinTouches, InpTPMultiplier, InpLotSize, InpMagicNumber);
   Print("Sinyaller yalnizca KAPANMIS mumlarda degerlendirilir. Acilista gecmise donuk islem acilmaz.");
   Print("Akis: trend -> dikdortgen (2+ temas) -> sahte kirilim -> kirilim kapanisi giris | SL direnc/destek disi, TP yukseklik x carpan");

   UpdatePanel();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(InpDeleteOnExit && g_object_prefix != "")
     {
      int total = ObjectsTotal(0, -1, -1);
      for(int i = total - 1; i >= 0; i--)
        {
         string name = ObjectName(0, i, -1, -1);
         if(StringFind(name, g_object_prefix) == 0)
            ObjectDelete(0, name);
        }
     }
   Comment("");
  }

void OnTick()
  {
   CheckNewBar();
   CheckTickExits();
   UpdatePanel();
  }

void OnTimer()
  {
   CheckNewBar();
   CheckTickExits();
   UpdatePanel();
  }

double OnTester()
  {
   // Strategy Tester optimizasyonunda net kari sirala.
   return TesterStatistics(STAT_PROFIT);
  }
//+------------------------------------------------------------------+
