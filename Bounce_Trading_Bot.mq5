//+------------------------------------------------------------------+
//|                                           Bounce_Trading_Bot.mq5 |
//|  Support & Resistance BOUNCE - MT5 ROBOT (EA) - Tam Otomatik     |
//|                                                                  |
//|  Kaynak: Trading Strategy Guides - "Bounce Trading Strategy in   |
//|  Forex" (Support and Resistance Bounce)                          |
//|  https://tradingstrategyguides.com/bounce-trading-strategy-in-forex/|
//|                                                                  |
//|  Bu bir UZMAN DANISMAN (robot) dosyasidir; gosterge degildir.    |
//|  Grafige eklenir, sinyal geldiginde emir acar/kapatir.           |
//|  Manuel mudahale gerekmez; tum kararlar KAPANMIS mumlarda alinir.|
//|                                                                  |
//|  MAKALENIN KURALLARI (ozet):                                     |
//|   1) Destek/direnc (S&R) bolgeleri ONCEDEN isaretlenir.          |
//|      (tepeler/dipler, trend cizgileri, kanallar, fibonacci,      |
//|      formasyonlar, psikolojik seviyeler)                         |
//|   2) Fiyat bolgeye yaklasinca "kirilim veya sicrama noktasi"     |
//|      olusur. Sicrama = fiyat seviyeyi gecmez, "saygi duyar".     |
//|   3) Uc giris yontemi:                                          |
//|      a) DOGRUDAN  : bolgeye dogrudan emir (en erken giris).      |
//|      b) ONAY      : bolgede durusunu teyit eden mum kalibi        |
//|                     (pin bar / engulfing) beklenir.              |
//|      c) FRACTAL   : bolgede bir fractal olusur, fiyat uzaklasir, |
//|                     karsi tarafta 2. fractal olusur; iki           |
//|                     seviyeden biri kirilirsa o yone girilir      |
//|                     (makale: 6-20 pip otesi).                    |
//|   4) TP = karsi taraftaki onceden bilinen S/R seviyesi.          |
//|   5) S&R ayni zamanda FILTRE: buyuk bir bariyere dogrudan        |
//|      giden kurulumlar alinmaz (yeterli alan yoksa islem yok).    |
//|   6) En yuksek olasilik: guclu S&R + trendin devami yonunde     |
//|      sicrama (veya cok guclu bolgede donus denemesi).            |
//|                                                                  |
//|  TASARIM KARARLARI (makalede oznel kalan noktalar - ayrintili    |
//|  aciklama README_Bounce_Bot.md icinde):                          |
//|   * S&R bolgeleri = swing pivot (tepe/dip) kumeleri. Her bolge   |
//|     icin temas sayisi, tolerans ve son temas zamani tutulur.     |
//|     InpLookbackBars penceresi ve InpPivotStrength kullanilir.    |
//|   * "Yakin/esit" temaslar = InpZoneToleranceATR x ATR mesafe     |
//|     icindeki pivotlar ayni bolgeye sayilir.                      |
//|   * Psikolojik seviyeler = InpUseRoundNumbers ile yuvarlak       |
//|     rakama (orn. 50 pip) yakin bolgeler +1 temas kazanir.        |
//|   * "Hakim trend" = EMA(fast)/EMA(slow) + kapanis konumu.        |
//|     InpUseTrendFilter: trend yonunde sicrama esas; istenirse     |
//|     cok guclu bolgede karsi-trend (donus) denemesi de alinir.   |
//|   * "Onay mumu" = pin bar (fitil >= InpPinWickRatio x govde)     |
//|     veya engulfing (yutan) mum; bolgeye temas etmis olmali.      |
//|   * "Fractal" = InpFractalStrength mum sag/sol ekstremi.         |
//|     Giris, karsi fractal + InpFractalBufferPips (makale: 6-20).  |
//|   * SL = bolgenin (veya 1. fractal'in) disi + ATR/point tamponu. |
//|     TP = karsi S/R bolgesinin yakin kenari; yoksa R/R ile       |
//|     InpFallbackTP_RR kullanilir.                                 |
//|                                                                  |
//|  GUVENLIK: Sinyaller YALNIZCA KAPANMIS mumlarda degerlendirilir. |
//|  Tek pozisyon (varsayilan), spread filtresi, risk % lot hesabi,  |
//|  gunluk limit, islem saatleri, para/sure cikislari dahildir.     |
//|  Once Strategy Tester'da test edin. Yatirim tavsiyesi degildir.  |
//+------------------------------------------------------------------+
#property copyright "Support & Resistance Bounce - MT5 Robot"
#property version   "1.00"
#property strict
#property description "S/R Bounce (Trading Strategy Guides) tam otomatik MT5 robotu"
#property description "Bolgeler pivotlardan kurulur; giris: dogrudan / mum onayi / fractal kirilimi"
#property description "TP: karsi S/R bolgesi | SL: bolge disi tampon | Filtre: bariyere alan kontrolu"
#property description "Sinyaller yalnizca kapanmis mumlarda degerlendirilir"

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Tipler                                                           |
//+------------------------------------------------------------------+
enum ENUM_BOUNCE_ENTRY
  {
   BOUNCE_CONFIRMATION = 0, // Mum onayi (pin bar / engulfing)
   BOUNCE_DIRECT       = 1, // Dogrudan bolgeye limit emir
   BOUNCE_FRACTAL      = 2  // Iki fractal kirilimi (6-20 pip)
  };

enum ENUM_BOUNCE_STATE
  {
   ST_IDLE     = 0,
   ST_ARMED    = 1,
   ST_TOUCH    = 2,
   ST_PENDING  = 3,
   ST_POSITION = 4
  };

struct Zone
  {
   double   price;       // bolge merkezi
   double   top;         // ust kenar
   double   bottom;      // alt kenar
   int      touches;     // temas sayisi
   datetime last_time;   // son temas zamani
   bool     round_level; // psikolojik (yuvarlak) seviye mi?
  };

//+------------------------------------------------------------------+
//| Girdiler                                                         |
//+------------------------------------------------------------------+
input group "1) Destek/Direnc bolgeleri (S&R)"
input ENUM_TIMEFRAMES InpTimeframe        = PERIOD_CURRENT; // Islem zaman dilimi (0 = grafik TF)
input int             InpLookbackBars     = 300;  // Bolge tarama penceresi (mum)
input int             InpPivotStrength    = 2;    // Pivot (tepe/dip) mum sayisi (her iki yan)
input int             InpMinTouches       = 2;    // Bolge gecerliligi icin min. temas (makale: tepeler/dipler)
input double          InpZoneToleranceATR = 0.6;  // Temas toleransi (ATR kati)
input double          InpApproachATR      = 0.5;  // Bolgeye "yaklasim" mesafesi (ATR kati)
input bool            InpUseRoundNumbers  = true; // Psikolojik (yuvarlak) seviyeleri guclendir
input int             InpRoundStepPips    = 50;   // Yuvarlak seviye adimi (pip)
input bool            InpUseTrendFilter   = true; // Hakim trend filtresi
input int             InpTrendFastEMA     = 20;   // Trend hizli EMA periyodu
input int             InpTrendSlowEMA     = 50;   // Trend yavas EMA periyodu
input bool            InpAllowCounterTrendStrong = true;  // Cok guclu bolgede karsi-trend (donus) izin
input int             InpStrongZoneTouches = 3;   // "Guclu bolge" esigi (temas)

input group "2) Giris yontemi (makale: 3 yol)"
input ENUM_BOUNCE_ENTRY InpEntryMethod    = BOUNCE_CONFIRMATION; // Giris yontemi
input int             InpDirectOffsetPoints = 10; // Dogrudan giris: bolge icine ofset (point)
input int             InpPendingExpireMinutes = 240; // Bekleyen emir gecerliligi (dk, 0 = GTC)
input bool            InpUsePinBar        = true; // Pin bar (fitilli donus mumu) onayi
input double          InpPinWickRatio     = 2.0;  // Pin bar: fitil / govde orani
input bool            InpUseEngulfing     = true; // Engulfing (yutan) mum onayi
input int             InpConfirmMaxBarsAfterTouch = 3; // Temas sonrasi max onay mumu
input int             InpFractalStrength  = 2;    // Fractal mum sayisi (her iki yan)
input int             InpFractalBufferPips = 10;  // Fractal girisi tamponu (pip, makale 6-20)
input int             InpFractalAwayPips  = 15;   // Iki fractal arasi min. mesafe (pip)
input bool            InpFractalFollowBreak = true; // Her iki fractal kirilimini de isle
input int             InpMaxWaitBars      = 50;   // Kurulum gecerlilik suresi (mum, 0 = sinirsiz)

input group "3) Cikis ve risk"
input double          InpSLBufferATR      = 0.5;  // SL tamponu (ATR kati)
input int             InpSLBufferPoints   = 10;   // SL tamponu (min. point)
input int             InpTPOffsetPoints   = 0;    // TP'yi karsi bolge kenarindan iceri cek (point)
input double          InpFallbackTP_RR    = 2.0;  // Karsi bolge yoksa TP = risk x bu carpan
input double          InpMinRR            = 1.0;  // Min. risk/odul orani
input double          InpMinTargetATR     = 1.0;  // Bariyere min. alan (ATR kati, 0 = kapali)
input double          InpLotSize          = 0.01; // Sabit lot
input bool            InpUseRiskPercent   = false; // Risk % ile lot hesabi
input double          InpRiskPercent      = 1.0;  // Islem basina risk (%)
input int             InpMagicNumber      = 20261118; // Magic number
input int             InpDeviationPoints  = 20;   // Maksimum sapma (point)
input int             InpMaxSpreadPoints  = 0;    // Maksimum spread (point) - 0 = kapali
input int             InpMaxOpenPositions = 1;    // Maksimum acik pozisyon (0 = sinirsiz)
input bool            InpAllowLongs       = true; // LONG islemler acik
input bool            InpAllowShorts      = true; // SHORT islemler acik
input double          InpMaxSL_ATR        = 3.0;  // SL mesafesi ATR x bu degeri asarsa islem atlanir (0 = kapali)
input double          InpMoneyTakeProfit  = 0.0;  // Para TP (hesap birimi, 0 = kapali)
input double          InpMoneyStopLoss    = 0.0;  // Para SL (hesap birimi, 0 = kapali)
input int             InpMaxPositionMinutes = 0;  // Maks. pozisyon suresi (dakika, 0 = kapali)
input double          InpMoveToBEAtRR     = 0.0;  // Kar R x bu kadar olunca SL'yi BE'ye cek (0 = kapali)

input group "4) Filtreler (otomatik koruma)"
input bool            InpUseTradingHours = false; // Islem saatleri filtresi
input int             InpStartHour       = 0;    // Baslangic saati (sunucu saati, 0-23)
input int             InpEndHour         = 24;   // Bitis saati (0-24, 24 = gece yarisi)
input int             InpMaxTradesPerDay = 0;    // Gunluk maks. islem (0 = sinirsiz)
input double          InpMaxDailyLoss    = 0.0;  // Gunluk maks. zarar (hesap birimi, 0 = kapali)

input group "5) Gorsel ve log"
input bool            InpDrawZones       = true; // S/R bolgelerini grafikte ciz
input bool            InpDrawArrows      = true; // Sinyal oklarini ciz
input bool            InpShowPanel       = true; // Bilgi panelini goster
input bool            InpDeleteOnExit    = true; // EA kaldirilinca grafik nesnelerini sil
input bool            InpLogSignals      = false; // Her mumda detayli log

//+------------------------------------------------------------------+
//| Globaller                                                        |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES g_tf = PERIOD_CURRENT;

int      g_ema_fast_handle = INVALID_HANDLE;
int      g_ema_slow_handle = INVALID_HANDLE;
int      g_atr_handle      = INVALID_HANDLE;
datetime g_last_bar_time   = 0;

ENUM_BOUNCE_STATE g_state = ST_IDLE;
int      g_side           = 0;     // aktif kurulum yonu: +1 LONG, -1 SHORT
Zone     g_zone;                   // aktif kurulum bolgesi
int      g_zone_touches   = 0;
datetime g_touch_time     = 0;
int      g_bars_since_touch = 0;
double   g_line1          = 0.0;   // 1. fractal (bolge tarafi)
double   g_line2          = 0.0;   // 2. fractal (karsi taraf)
datetime g_line1_time     = 0;

double   g_planned_entry  = 0.0;
double   g_planned_sl     = 0.0;
double   g_planned_tp     = 0.0;

datetime g_signal_time    = 0;
double   g_signal_high    = 0.0;
double   g_signal_low     = 0.0;

Zone     g_zones_sup[];
Zone     g_zones_res[];
int      g_nsup = 0;
int      g_nres = 0;
Zone     g_sup;  bool g_sup_ok = false;
Zone     g_res;  bool g_res_ok = false;

int      g_current_trend  = 0;
int      g_signal_count   = 0;
int      g_skip_count     = 0;
int      g_trades_today   = 0;
datetime g_trades_day     = 0;
double   g_day_start_equity = 0.0;
string   g_last_action    = "Baslatiliyor";
string   g_object_prefix  = "";

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

string MethodName()
  {
   switch(InpEntryMethod)
     {
      case BOUNCE_DIRECT:  return "DOGRUDAN (limit)";
      case BOUNCE_FRACTAL: return "FRACTAL KIRILIMI";
      default:             return "MUM ONAYI";
     }
  }

string StateName()
  {
   switch(g_state)
     {
      case ST_ARMED:    return "BOLGE YAKIN (tetik bekleniyor)";
      case ST_TOUCH:    return "1. FRACTAL HAZIR (karsi fractal bekleniyor)";
      case ST_PENDING:  return "BEKLEYEN EMIR AKTIF";
      case ST_POSITION: return "POZISYON ACIK";
      default:          return "IDLE (S/R bolgesi bekleniyor)";
     }
  }

double TickSize()
  {
   double size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(size <= 0.0)
      size = _Point;
   return size;
  }

// 1 pip = 10 point (3/5 haneli FX sembolleri), digerlerinde 1 point
double PipSize()
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5)
      return _Point * 10.0;
   return _Point;
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

int BarsBetween(const datetime from, const datetime to)
  {
   int secs = PeriodSeconds(g_tf);
   if(secs <= 0 || to <= from)
      return 0;
   return (int)((to - from) / secs);
  }

double ZoneTolerance(const double atr1)
  {
   return MathMax(InpZoneToleranceATR * atr1, _Point * 10.0);
  }

bool IsNearRoundNumber(const double price, const double tol)
  {
   double step = InpRoundStepPips * PipSize();
   if(step <= 0.0)
      return false;
   double r = MathMod(price, step);
   return (r <= tol || (step - r) <= tol);
  }

//+------------------------------------------------------------------+
//| Pozisyon ve bekleyen emir yardimcilari                           |
//+------------------------------------------------------------------+
bool SelectOurPosition(const ulong ticket)
  {
   if(ticket == 0)
      return false;
   if(!PositionSelectByTicket(ticket))
      return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC) != (ulong)InpMagicNumber)
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

int CountOurPending()
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != (ulong)InpMagicNumber)
         continue;
      long type = OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT ||
         type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP ||
         type == ORDER_TYPE_BUY_STOP_LIMIT || type == ORDER_TYPE_SELL_STOP_LIMIT)
         count++;
     }
   return count;
  }

void DeleteOurPending(const string reason)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != (ulong)InpMagicNumber)
         continue;
      long type = OrderGetInteger(ORDER_TYPE);
      if(type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT &&
         type != ORDER_TYPE_BUY_STOP && type != ORDER_TYPE_SELL_STOP &&
         type != ORDER_TYPE_BUY_STOP_LIMIT && type != ORDER_TYPE_SELL_STOP_LIMIT)
         continue;
      if(trade.OrderDelete(ticket))
         PrintFormat("BEKLEYEN EMIR SILINDI: ticket=%I64u (%s)", ticket, reason);
      else
         PrintFormat("Bekleyen emir silinemedi: ticket=%I64u retcode=%u (%s)",
                     ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
     }
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
   double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   bool   sent   = trade.PositionClose(ticket, InpDeviationPoints);
   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Kapatma basarisiz: ticket=%I64u sebep=%s retcode=%u (%s)",
                  ticket, reason, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return false;
     }
   PrintFormat("KAPATILDI: ticket=%I64u sebep=%s kar=%.2f", ticket, reason, profit);
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

// Hakim trend: EMA fast/slow iliskisi + kapanis konumu (makale: trend yonu)
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

int CountDealsToday(const datetime day_start)
  {
   if(!HistorySelect(day_start, TimeCurrent() + 60))
      return 0;
   int total = HistoryDealsTotal();
   int count = 0;
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)InpMagicNumber)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
         continue;
      if((int)HistoryDealGetInteger(ticket, DEAL_ENTRY) != (int)DEAL_ENTRY_IN)
         continue;
      count++;
     }
   return count;
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
      g_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
     }
   g_trades_today = CountDealsToday(day_start);
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

// Trend yonunde mi? Makale: en yuksek olasilik trend devami; guclu bolgede donus de mumkun.
bool TrendAllows(const int side, const int touches)
  {
   if(!InpUseTrendFilter)
      return true;
   if(side > 0 && g_current_trend > 0)
      return true;
   if(side < 0 && g_current_trend < 0)
      return true;
   if(InpAllowCounterTrendStrong && touches >= InpStrongZoneTouches)
      return true;
   return false;
  }

//+------------------------------------------------------------------+
//| S/R bolge kurulumu                                               |
//+------------------------------------------------------------------+
// i indeksindeki mum, sag/sol "strength" mumdan buyuk/kucuk mu?
bool IsPivot(const MqlRates &rates[], const int idx, const int strength, const bool want_high)
  {
   int n = ArraySize(rates);
   if(idx - strength < 1)      // sadece kapanmis mumlar
      return false;
   if(idx + strength >= n)
      return false;
   double v = (want_high ? rates[idx].high : rates[idx].low);
   for(int k = 1; k <= strength; k++)
     {
      if(want_high)
        {
         if(rates[idx - k].high >= v)
            return false;
         if(rates[idx + k].high >= v)
            return false;
        }
      else
        {
         if(rates[idx - k].low <= v)
            return false;
         if(rates[idx + k].low <= v)
            return false;
        }
     }
   return true;
  }

// Pivotlardan bolgeler: yakin pivotlar tek bolgede toplanir (temas sayisi = guc).
void BuildZones(const MqlRates &rates[], const double atr1, const bool want_highs, Zone &zones[])
  {
   ArrayResize(zones, 0);
   int n = ArraySize(rates);
   if(n < 30)
      return;
   int strength = InpPivotStrength;
   int limit = MathMin(InpLookbackBars, n - strength - 2);
   if(limit <= strength + 2)
      return;

   double prices[];
   datetime times[];
   ArrayResize(prices, 0);
   ArrayResize(times, 0);
   int cnt = 0;
   for(int i = strength + 1; i <= limit; i++)
     {
      if(!IsPivot(rates, i, strength, want_highs))
         continue;
      ArrayResize(prices, cnt + 1);
      ArrayResize(times, cnt + 1);
      prices[cnt] = (want_highs ? rates[i].high : rates[i].low);
      times[cnt]  = rates[i].time;
      cnt++;
     }
   if(cnt < InpMinTouches)
      return;

   // fiyata gore artan siralama (eklemeli)
   for(int i = 1; i < cnt; i++)
     {
      double p = prices[i];
      datetime t = times[i];
      int j = i - 1;
      while(j >= 0 && prices[j] > p)
        {
         prices[j + 1] = prices[j];
         times[j + 1]  = times[j];
         j--;
        }
      prices[j + 1] = p;
      times[j + 1]  = t;
     }

   double tol = ZoneTolerance(atr1);
   int start = 0;
   while(start < cnt)
     {
      double sum = 0.0, mn = prices[start], mx = prices[start], avg = prices[start];
      datetime last = times[start];
      int k = start, count = 0;
      while(k < cnt && (prices[k] - avg) <= tol)
        {
         sum += prices[k];
         mn = MathMin(mn, prices[k]);
         mx = MathMax(mx, prices[k]);
         if(times[k] > last)
            last = times[k];
         count++;
         avg = sum / count;
         k++;
        }
      if(count >= InpMinTouches)
        {
         Zone z;
         z.price      = avg;
         z.top        = MathMax(mx, avg + tol * 0.25);
         z.bottom     = MathMin(mn, avg - tol * 0.25);
         z.touches    = count;
         z.last_time  = last;
         z.round_level = false;
         if(InpUseRoundNumbers && IsNearRoundNumber(avg, tol))
           {
            z.round_level = true;
            z.touches     = count + 1;   // psikolojik seviye bonusu
           }
         int idx = ArraySize(zones);
         ArrayResize(zones, idx + 1);
         zones[idx] = z;
        }
      start = (k > start ? k : start + 1);
     }
  }

void BuildZoneSets(const MqlRates &rates[], const double atr1, const double price)
  {
   BuildZones(rates, atr1, false, g_zones_sup);
   BuildZones(rates, atr1, true,  g_zones_res);
   g_nsup = ArraySize(g_zones_sup);
   g_nres = ArraySize(g_zones_res);

   g_sup_ok = false;
   for(int i = g_nsup - 1; i >= 0; i--)
     {
      if(g_zones_sup[i].top < price)
        {
         g_sup    = g_zones_sup[i];
         g_sup_ok = true;
         break;
        }
     }
   g_res_ok = false;
   for(int i = 0; i < g_nres; i++)
     {
      if(g_zones_res[i].bottom > price)
        {
         g_res    = g_zones_res[i];
         g_res_ok = true;
         break;
        }
     }
  }

bool FindZoneAbove(const double price, Zone &out)
  {
   for(int i = 0; i < g_nres; i++)
     {
      if(g_zones_res[i].bottom > price)
        {
         out = g_zones_res[i];
         return true;
        }
     }
   return false;
  }

bool FindZoneBelow(const double price, Zone &out)
  {
   for(int i = g_nsup - 1; i >= 0; i--)
     {
      if(g_zones_sup[i].top < price)
        {
         out = g_zones_sup[i];
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Plan: SL (bolge disi) + TP (karsi S/R bolgesi)                   |
//+------------------------------------------------------------------+
bool BuildPlan(const int side, const double sl_ref, const double entry_hint,
               const double atr1, double &sl, double &tp, string &reason)
  {
   reason = "";
   if(side == 0 || sl_ref <= 0.0 || entry_hint <= 0.0)
     {
      reason = "gecersiz parametre";
      return false;
     }
   double buffer = MathMax(InpSLBufferATR * atr1, InpSLBufferPoints * _Point);
   sl = NormalizePriceToTick(sl_ref - side * buffer, (side > 0 ? -1 : 1));
   if(side > 0 && sl >= entry_hint)
     {
      reason = "SL giris uzerinde kaldi";
      return false;
     }
   if(side < 0 && sl <= entry_hint)
     {
      reason = "SL giris altinda kaldi";
      return false;
     }
   double risk = MathAbs(entry_hint - sl);
   if(risk <= 0.0)
     {
      reason = "SL mesafesi sifir";
      return false;
     }
   if(InpMaxSL_ATR > 0.0 && risk > InpMaxSL_ATR * atr1)
     {
      reason = StringFormat("SL cok genis (%.1f x ATR)", risk / atr1);
      return false;
     }

   Zone target;
   bool have = (side > 0 ? FindZoneAbove(entry_hint, target) : FindZoneBelow(entry_hint, target));
   double tp_price = 0.0;
   if(have)
     {
      double cand = (side > 0 ? target.bottom - InpTPOffsetPoints * _Point
                              : target.top + InpTPOffsetPoints * _Point);
      double room = side * (cand - entry_hint);
      if(room <= 0.0)
         have = false;
      else if(InpMinTargetATR > 0.0 && room < InpMinTargetATR * atr1)
        {
         // Makale filtresi: buyuk bariyere fazla yakin giris yapma
         reason = StringFormat("hedef bolge cok yakin (%.2f x ATR)", room / atr1);
         return false;
        }
      else
         tp_price = cand;
     }
   if(!have)
      tp_price = entry_hint + side * InpFallbackTP_RR * risk;

   double reward = MathAbs(tp_price - entry_hint);
   if(reward <= 0.0)
     {
      reason = "TP mesafesi sifir";
      return false;
     }
   if(reward / risk < InpMinRR)
     {
      reason = StringFormat("R/R dusuk (%.2f)", reward / risk);
      return false;
     }
   tp = NormalizePriceToTick(tp_price, (side > 0 ? -1 : 1));
   return true;
  }

//+------------------------------------------------------------------+
//| Lot hesabi                                                       |
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
   double equity       = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_money   = equity * InpRiskPercent / 100.0;
   double loss_per_lot = (sl_distance / tick_size) * tick_value;
   if(loss_per_lot <= 0.0)
      return 0.0;
   return NormalizeVolume(risk_money / loss_per_lot);
  }

//+------------------------------------------------------------------+
//| Grafik nesneleri                                                 |
//+------------------------------------------------------------------+
void DrawSignalArrow(const datetime bar_time, const double high, const double low, const int side)
  {
   if(!InpDrawArrows || bar_time <= 0)
      return;
   string name = g_object_prefix + "SIG_" + IntegerToString((long)bar_time) +
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

void DrawZoneBox(const string tag, const Zone &z, const bool valid, const color c)
  {
   string name = g_object_prefix + "ZONE_" + tag;
   if(!InpDrawZones)
      return;
   ObjectDelete(0, name);
   if(!valid || z.top <= z.bottom)
      return;
   int secs = PeriodSeconds(g_tf);
   datetime right = iTime(_Symbol, g_tf, 0) + secs * 10;
   datetime left  = (z.last_time > 0 ? z.last_time : right - secs * 60);
   if(left >= right)
      left = right - secs * 20;
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, left, z.top, right, z.bottom))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
  }

void DrawZones()
  {
   if(!InpDrawZones)
      return;
   DrawZoneBox("SUP", g_sup, g_sup_ok, clrSeaGreen);
   DrawZoneBox("RES", g_res, g_res_ok, clrIndianRed);
  }

//+------------------------------------------------------------------+
//| Kurulum durumu                                                   |
//+------------------------------------------------------------------+
void ResetSetupValues()
  {
   g_state            = ST_IDLE;
   g_side             = 0;
   g_zone_touches     = 0;
   g_touch_time       = 0;
   g_bars_since_touch = 0;
   g_line1            = 0.0;
   g_line2            = 0.0;
   g_line1_time       = 0;
   g_planned_entry    = 0.0;
   g_planned_sl       = 0.0;
   g_planned_tp       = 0.0;
   g_signal_time      = 0;
   g_signal_high      = 0.0;
   g_signal_low       = 0.0;
  }

void EnteredPositionState(const int side)
  {
   g_side             = side;
   g_state            = ST_POSITION;
   g_line1            = 0.0;
   g_line2            = 0.0;
   g_line1_time       = 0;
   g_touch_time       = 0;
   g_bars_since_touch = 0;
  }

void ResetSetup(const string reason)
  {
   if(g_state == ST_PENDING)
      DeleteOurPending("kurulum sifirlandi: " + reason);
   if(InpLogSignals && reason != "")
      PrintFormat("KURULUM SIFIRLANDI: %s", reason);
   if(reason != "")
      g_last_action = "Sifirlandi: " + reason;
   ResetSetupValues();
  }

//+------------------------------------------------------------------+
//| Emir gonderme                                                    |
//+------------------------------------------------------------------+
bool PlacePendingOrder(const int side, const ENUM_ORDER_TYPE type, const double price,
                       const double sl, const double tp, const string comment)
  {
   if(InpMaxOpenPositions > 0 && CountOurPositions(0) + CountOurPending() >= InpMaxOpenPositions + 1)
     {
      PrintFormat("Bekleyen emir siniri: acik=%d bekleyen=%d", CountOurPositions(0), CountOurPending());
      return false;
     }
   double volume = CalcLot(side, price, sl);
   if(volume <= 0.0)
     {
      PrintFormat("Lot hesabi gecersiz: entry=%.*f sl=%.*f", _Digits, price, _Digits, sl);
      return false;
     }
   ENUM_ORDER_TYPE_TIME tt = ORDER_TIME_GTC;
   datetime exp = 0;
   if(InpPendingExpireMinutes > 0)
     {
      tt  = ORDER_TIME_SPECIFIED;
      exp = TimeCurrent() + (datetime)(MathMax(10, InpPendingExpireMinutes) * 60);
     }
   double p  = NormalizePriceToTick(price, 0);
   double nsl = NormalizePriceToTick(sl, 0);
   double ntp = NormalizePriceToTick(tp, 0);
   bool sent = false;
   if(type == ORDER_TYPE_BUY_LIMIT)
      sent = trade.BuyLimit(volume, NormalizePriceToTick(p, -1), _Symbol, nsl, ntp, tt, exp, comment);
   else if(type == ORDER_TYPE_SELL_LIMIT)
      sent = trade.SellLimit(volume, NormalizePriceToTick(p, 1), _Symbol, nsl, ntp, tt, exp, comment);
   else if(type == ORDER_TYPE_BUY_STOP)
      sent = trade.BuyStop(volume, NormalizePriceToTick(p, 1), _Symbol, nsl, ntp, tt, exp, comment);
   else if(type == ORDER_TYPE_SELL_STOP)
      sent = trade.SellStop(volume, NormalizePriceToTick(p, -1), _Symbol, nsl, ntp, tt, exp, comment);
   else
      return false;

   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Bekleyen emir hatasi: %s | tip=%s fiyat=%.*f sl=%.*f tp=%.*f retcode=%u (%s)",
                  comment, EnumToString(type), _Digits, p, _Digits, nsl, _Digits, ntp,
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
      g_last_action = "Bekleyen emir broker tarafindan reddedildi";
      return false;
     }
   PrintFormat("BEKLEYEN EMIR: %s | tip=%s fiyat=%.*f SL=%.*f TP=%.*f lot=%.8f",
               comment, EnumToString(type), _Digits, p, _Digits, nsl, _Digits, ntp, volume);
   return true;
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

   long stops_level  = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_distance = MathMax((double)stops_level, (double)freeze_level) * _Point;
   if(sl > 0.0 && MathAbs(entry - sl) < min_distance + TickSize())
     {
      g_skip_count++;
      g_last_action = "SL broker minimum mesafesinden kucuk, islem atlandi";
      return false;
     }
   if(tp > 0.0 && MathAbs(tp - entry) < min_distance + TickSize())
     {
      g_skip_count++;
      g_last_action = "TP broker minimum mesafesinden kucuk, islem atlandi";
      return false;
     }
   if(sl > 0.0 && InpMaxSL_ATR > 0.0)
     {
      double atr = 0.0;
      if(GetATR(1, atr) && atr > 0.0 && MathAbs(entry - sl) > InpMaxSL_ATR * atr)
        {
         g_skip_count++;
         g_last_action = "SL mesafesi ATR filtresini asti";
         return false;
        }
     }

   double volume = CalcLot(side, entry, sl);
   if(volume <= 0.0)
     {
      g_last_action = "Lot hacmi broker sinirlarina uymuyor";
      return false;
     }

   string comment = (side > 0 ? "BOUNCE BUY" : "BOUNCE SELL");
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
   DrawSignalArrow(signal_time, sig_high, sig_low, side);
   g_planned_entry = entry;
   g_planned_sl    = sl;
   g_planned_tp    = tp;
   g_signal_time   = signal_time;
   g_signal_high   = sig_high;
   g_signal_low    = sig_low;
   PrintFormat("GIRIS: %s | yon=%s | sinyal mumu=%s | lot=%.8f | fiyat=%.*f | SL=%.*f | TP=%.*f",
               signal_text, SideName(side), TimeToString(signal_time), volume,
               _Digits, entry, _Digits, sl, _Digits, tp);
   g_last_action = StringFormat("%s islem acildi (%s)", SideName(side), signal_text);
   return true;
  }

//+------------------------------------------------------------------+
//| Mum onayi (pin bar / engulfing)                                  |
//+------------------------------------------------------------------+
bool IsConfirmation(const MqlRates &rates[], const int idx, const int side, const double atr1)
  {
   int n = ArraySize(rates);
   if(idx + 1 >= n)
      return false;
   MqlRates c = rates[idx];
   double tol   = ZoneTolerance(atr1);
   double range = c.high - c.low;
   if(range <= 0.0)
      return false;
   double body  = MathAbs(c.close - c.open);

   bool touched = (side > 0 ? (c.low <= g_zone.top + tol * 0.25)
                            : (c.high >= g_zone.bottom - tol * 0.25));
   if(!touched)
      return false;

   if(side > 0)
     {
      if(c.close < g_zone.bottom)
         return false;                       // bolge altina kapanis = kirilim
      if(InpUsePinBar)
        {
         double lower = MathMin(c.open, c.close) - c.low;
         double upper = c.high - MathMax(c.open, c.close);
         if(lower >= InpPinWickRatio * MathMax(body, TickSize()) &&
            lower >= upper && c.close >= c.low + 0.5 * range)
            return true;
        }
      if(InpUseEngulfing)
        {
         MqlRates p = rates[idx + 1];
         if(c.close > c.open && p.close < p.open &&
            c.close >= p.open && c.open <= p.close &&
            body > MathAbs(p.close - p.open))
            return true;
        }
     }
   else
     {
      if(c.close > g_zone.top)
         return false;
      if(InpUsePinBar)
        {
         double upper = c.high - MathMax(c.open, c.close);
         double lower = MathMin(c.open, c.close) - c.low;
         if(upper >= InpPinWickRatio * MathMax(body, TickSize()) &&
            upper >= lower && c.close <= c.high - 0.5 * range)
            return true;
        }
      if(InpUseEngulfing)
        {
         MqlRates p = rates[idx + 1];
         if(c.close < c.open && p.close > p.open &&
            c.close <= p.open && c.open >= p.close &&
            body > MathAbs(p.close - p.open))
            return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Fractal yardimcilari                                             |
//+------------------------------------------------------------------+
bool FindZonePivot(const MqlRates &rates[], const int side, const double atr1, int &idx_out)
  {
   int n = ArraySize(rates);
   int strength = InpFractalStrength;
   int start = strength + 1;
   int end = MathMin(n - strength - 1, start + 30);
   double tol = ZoneTolerance(atr1);
   for(int i = start; i <= end; i++)
     {
      if(!IsPivot(rates, i, strength, (side < 0)))
         continue;
      double p = (side > 0 ? rates[i].low : rates[i].high);
      if(p >= g_zone.bottom - tol && p <= g_zone.top + tol)
        {
         idx_out = i;
         return true;
        }
     }
   return false;
  }

bool FindOppositePivot(const MqlRates &rates[], const int side, const double atr1,
                       double &price_out, datetime &time_out)
  {
   int n = ArraySize(rates);
   int strength = InpFractalStrength;
   int start = strength + 1;
   int end = MathMin(n - strength - 1, start + 60);
   double pip = PipSize();
   double away = InpFractalAwayPips * pip;
   for(int i = start; i <= end; i++)
     {
      if(rates[i].time <= g_line1_time)
         continue;
      if(side > 0)
        {
         if(!IsPivot(rates, i, strength, true))
            continue;
         if(rates[i].high >= g_line1 + away)
           {
            price_out = rates[i].high;
            time_out  = rates[i].time;
            return true;
           }
        }
      else
        {
         if(!IsPivot(rates, i, strength, false))
            continue;
         if(rates[i].low <= g_line1 - away)
           {
            price_out = rates[i].low;
            time_out  = rates[i].time;
            return true;
           }
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Durum makinesi                                                   |
//+------------------------------------------------------------------+
void ProcessFirstFractal(const MqlRates &rates[], const double atr1);

bool TrendStillValid()
  {
   if(!InpUseTrendFilter)
      return true;
   if(g_current_trend == 0)
      return true;
   if(g_current_trend == g_side)
      return true;
   if(InpAllowCounterTrendStrong && g_zone_touches >= InpStrongZoneTouches)
      return true;
   return false;
  }

void TryArmSetup(const MqlRates &rates[], const double atr1, const double close1)
  {
   double approach = MathMax(InpApproachATR * atr1, _Point * 5.0);

   bool sup_near = (g_sup_ok && close1 >= g_sup.top && (close1 - g_sup.top) <= approach);
   bool res_near = (g_res_ok && close1 <= g_res.bottom && (g_res.bottom - close1) <= approach);

   if(sup_near && !TrendAllows(1, g_sup.touches))
      sup_near = false;
   if(res_near && !TrendAllows(-1, g_res.touches))
      res_near = false;

   int side = 0;
   if(sup_near && res_near)
      side = ((close1 - g_sup.top) <= (g_res.bottom - close1) ? 1 : -1);
   else if(sup_near)
      side = 1;
   else if(res_near)
      side = -1;

   if(side == 0)
     {
      g_last_action = "Fiyat bir S/R bolgesine yaklasmadi";
      return;
     }
   if(side > 0 && !InpAllowLongs)
      return;
   if(side < 0 && !InpAllowShorts)
      return;
   if(!WithinTradingHours() || !DailyLimitsOK())
     {
      g_last_action = "Filtre: saat / gunluk limit";
      return;
     }

   Zone zone = (side > 0 ? g_sup : g_res);
   double sl_ref = (side > 0 ? zone.bottom : zone.top);

   // On kontrol: plan mantikli mi? (giris tahmini bolge kenari)
   double pre_entry = (side > 0 ? zone.top : zone.bottom);
   double psl = 0.0, ptp = 0.0;
   string reason = "";
   if(!BuildPlan(side, sl_ref, pre_entry, atr1, psl, ptp, reason))
     {
      g_skip_count++;
      g_last_action = "Kurulum elendi: " + reason;
      if(InpLogSignals)
         PrintFormat("ELENDI: %s | bolge=%.*f..%.*f temas=%d | %s",
                     SideName(side), _Digits, zone.bottom, _Digits, zone.top,
                     zone.touches, reason);
      return;
     }

   g_side         = side;
   g_zone         = zone;
   g_zone_touches = zone.touches;
   g_bars_since_touch = 0;
   g_touch_time   = 0;
   g_line1        = 0.0;
   g_line2        = 0.0;
   g_line1_time   = 0;

   if(InpEntryMethod == BOUNCE_DIRECT)
     {
      double entry = (side > 0 ? zone.top - InpDirectOffsetPoints * _Point
                               : zone.bottom + InpDirectOffsetPoints * _Point);
      double sl = 0.0, tp = 0.0;
      string why = "";
      if(!BuildPlan(side, sl_ref, entry, atr1, sl, tp, why))
        {
         g_skip_count++;
         g_last_action = "Dogrudan giris elendi: " + why;
         ResetSetupValues();
         return;
        }
      ENUM_ORDER_TYPE otype = (side > 0 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT);
      string comment = (side > 0 ? "BOUNCE BUY LMT" : "BOUNCE SELL LMT");
      if(!PlacePendingOrder(side, otype, entry, sl, tp, comment))
        {
         ResetSetupValues();
         return;
        }
      g_planned_entry = entry;
      g_planned_sl    = sl;
      g_planned_tp    = tp;
      g_signal_time   = rates[1].time;
      g_signal_high   = rates[1].high;
      g_signal_low    = rates[1].low;
      g_state         = ST_PENDING;
      g_last_action   = StringFormat("%s limit emri yerlestirildi (%.*f)", SideName(side), _Digits, entry);
      PrintFormat("KURULUM (dogrudan): %s | bolge=%.*f..%.*f temas=%d | limit=%.*f SL=%.*f TP=%.*f",
                  SideName(side), _Digits, zone.bottom, _Digits, zone.top, zone.touches,
                  _Digits, entry, _Digits, sl, _Digits, tp);
      return;
     }

   g_state       = ST_ARMED;
   g_last_action = StringFormat("%s bolgesine yaklasim, tetik bekleniyor", SideName(side));
   PrintFormat("KURULUM (%s): %s | bolge=%.*f..%.*f temas=%d | trend=%s",
               MethodName(), SideName(side), _Digits, zone.bottom, _Digits, zone.top,
               zone.touches, TrendName(g_current_trend));
  }

void ProcessArmed(const MqlRates &rates[], const double atr1)
  {
   if(g_side == 0)
     {
      ResetSetup("yon yok");
      return;
     }
   if(!TrendStillValid())
     {
      ResetSetup("trend ters dondu");
      return;
     }

   double tol = ZoneTolerance(atr1);
   bool touched_now = (g_side > 0 ? (rates[1].low <= g_zone.top + tol * 0.25)
                                  : (rates[1].high >= g_zone.bottom - tol * 0.25));

   // Bolge kapanisla kirildi mi? (makale: kirilim = baska bir oyun)
   if(g_side > 0 && rates[1].close < g_zone.bottom - tol * 0.25)
     {
      ResetSetup("destek kapanisla kirildi");
      return;
     }
   if(g_side < 0 && rates[1].close > g_zone.top + tol * 0.25)
     {
      ResetSetup("direnc kapanisla kirildi");
      return;
     }

   if(InpEntryMethod == BOUNCE_CONFIRMATION)
     {
      if(touched_now && g_touch_time == 0)
        {
         g_touch_time       = rates[1].time;
         g_bars_since_touch = 0;
        }
      if(g_touch_time == 0)
        {
         g_last_action = "Bolgeye temas bekleniyor";
         return;
        }
      if(BarsBetween(g_touch_time, rates[1].time) > InpConfirmMaxBarsAfterTouch)
        {
         ResetSetup("onay mumu gelmedi (sure)");
         return;
        }
      if(!IsConfirmation(rates, 1, g_side, atr1))
        {
         g_last_action = "Onay mumu (pin bar / engulfing) bekleniyor";
         return;
        }

      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
         return;
      double entry  = (g_side > 0 ? tick.ask : tick.bid);
      double sl_ref = (g_side > 0 ? MathMin(g_zone.bottom, rates[1].low)
                                  : MathMax(g_zone.top, rates[1].high));
      double sl = 0.0, tp = 0.0;
      string why = "";
      if(!BuildPlan(g_side, sl_ref, entry, atr1, sl, tp, why))
        {
         g_skip_count++;
         ResetSetup("plan reddedildi: " + why);
         return;
        }
      if(OpenTrade(g_side, sl, tp, "S/R sicrama + mum onayi",
                   rates[1].time, rates[1].high, rates[1].low))
        {
         EnteredPositionState(g_side);
        }
      return;
     }

   if(InpEntryMethod == BOUNCE_FRACTAL)
     {
      int idx = 0;
      if(!FindZonePivot(rates, g_side, atr1, idx))
        {
         g_last_action = "Bolgede 1. fractal bekleniyor";
         return;
        }
      g_line1      = (g_side > 0 ? rates[idx].low : rates[idx].high);
      g_line1_time = rates[idx].time;
      g_bars_since_touch = 0;
      g_state      = ST_TOUCH;
      g_last_action = StringFormat("1. fractal: %.*f", _Digits, g_line1);
      PrintFormat("FRACTAL 1: %s | seviye=%.*f | zaman=%s | bolge=%.*f..%.*f",
                  SideName(g_side), _Digits, g_line1, TimeToString(g_line1_time),
                  _Digits, g_zone.bottom, _Digits, g_zone.top);
      ProcessFirstFractal(rates, atr1);
      return;
     }
  }

void ProcessFirstFractal(const MqlRates &rates[], const double atr1)
  {
   if(g_side == 0 || g_line1 <= 0.0)
     {
      ResetSetup("fractal eksik");
      return;
     }
   if(!TrendStillValid())
     {
      ResetSetup("trend ters dondu");
      return;
     }
   double tol = ZoneTolerance(atr1);
   if(g_side > 0 && rates[1].close < g_line1 - tol * 0.25)
     {
      ResetSetup("1. fractal asagi kirildi");
      return;
     }
   if(g_side < 0 && rates[1].close > g_line1 + tol * 0.25)
     {
      ResetSetup("1. fractal yukari kirildi");
      return;
     }

   double line2_price = 0.0;
   datetime line2_time = 0;
   if(!FindOppositePivot(rates, g_side, atr1, line2_price, line2_time))
     {
      g_last_action = "2. (karsi) fractal bekleniyor";
      return;
     }
   g_line2 = line2_price;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
      return;
   double close1    = rates[1].close;
   double buf_price = InpFractalBufferPips * PipSize();

   // 1) Sicrama yonu (karsi fractal kirilimi)
   double entry1 = (g_side > 0 ? g_line2 + buf_price : g_line2 - buf_price);
   double sl_ref1 = (g_side > 0 ? g_line1 : g_line2);
   bool   market1 = (g_side > 0 ? (entry1 <= close1) : (entry1 >= close1));

   double sl = 0.0, tp = 0.0;
   string why = "";
   double entry_used = (market1 ? (g_side > 0 ? tick.ask : tick.bid) : entry1);
   if(!BuildPlan(g_side, sl_ref1, entry_used, atr1, sl, tp, why))
     {
      g_skip_count++;
      ResetSetup("fractal plani reddedildi: " + why);
      return;
     }

   if(market1)
     {
      if(OpenTrade(g_side, sl, tp, "S/R sicrama (fractal kirilimi)",
                   line2_time, MathMax(line2_price, entry1), MathMin(line2_price, entry1)))
        {
         EnteredPositionState(g_side);
         DeleteOurPending("yeni giris");
        }
      return;
     }

   ENUM_ORDER_TYPE otype1 = (g_side > 0 ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP);
   string comment1 = (g_side > 0 ? "BOUNCE BUY STP" : "BOUNCE SELL STP");
   if(!PlacePendingOrder(g_side, otype1, entry1, sl, tp, comment1))
     {
      ResetSetup("stop emir yerlestirilemedi");
      return;
     }
   g_planned_entry = entry1;
   g_planned_sl    = sl;
   g_planned_tp    = tp;
   g_signal_time   = line2_time;
   g_signal_high   = MathMax(line2_price, entry1);
   g_signal_low    = MathMin(line2_price, entry1);

   // 2) Ters kirilim (1. fractal kirilirsa) - makale: "iki seviyeden biri kazanir"
   if(InpFractalFollowBreak)
     {
      double entry2  = (g_side > 0 ? g_line1 - buf_price : g_line1 + buf_price);
      double sl_ref2 = (g_side > 0 ? g_line2 : g_line1);
      double entry2_used = entry2;
      if(g_side > 0 && entry2 >= tick.bid)
         entry2_used = 0.0;
      if(g_side < 0 && entry2 <= tick.ask)
         entry2_used = 0.0;
      if(entry2_used > 0.0)
        {
         double sl2 = 0.0, tp2 = 0.0;
         string why2 = "";
         if(BuildPlan(-g_side, sl_ref2, entry2_used, atr1, sl2, tp2, why2))
           {
            ENUM_ORDER_TYPE otype2 = (g_side > 0 ? ORDER_TYPE_SELL_STOP : ORDER_TYPE_BUY_STOP);
            string comment2 = (g_side > 0 ? "BREAK SELL STP" : "BREAK BUY STP");
            PlacePendingOrder(-g_side, otype2, entry2, sl2, tp2, comment2);
           }
         else if(InpLogSignals)
            PrintFormat("Ters kirilim emri atlandi: %s", why2);
        }
     }

   g_state       = ST_PENDING;
   g_bars_since_touch = 0;
   g_last_action = StringFormat("Iki fractal hazir: %.*f / %.*f, kirilim bekleniyor",
                                _Digits, g_line1, _Digits, g_line2);
   PrintFormat("FRACTAL 2: %s | seviye=%.*f | stop emir=%.*f | SL=%.*f | TP=%.*f",
               SideName(g_side), _Digits, g_line2, _Digits, entry1, _Digits, sl, _Digits, tp);
  }

void ProcessPending(const MqlRates &rates[], const double atr1, const double close1)
  {
   if(CountOurPending() == 0)
     {
      ResetSetup("bekleyen emir kalmadi");
      return;
     }
   if(!TrendStillValid())
     {
      ResetSetup("trend ters dondu (bekleyen iptal)");
      return;
     }
   double tol = ZoneTolerance(atr1);
   if(InpEntryMethod == BOUNCE_DIRECT)
     {
      if(g_side > 0 && close1 < g_zone.bottom - tol * 0.5)
        {
         ResetSetup("destek kirildi, limit iptal");
         return;
        }
      if(g_side < 0 && close1 > g_zone.top + tol * 0.5)
        {
         ResetSetup("direnc kirildi, limit iptal");
         return;
        }
     }
   g_last_action = "Bekleyen emir(ler) aktif, tetikleme bekleniyor";
  }

void CheckPendingFills()
  {
   if(g_state != ST_PENDING)
      return;
   if(CountOurPositions(0) > 0)
     {
      int side = g_side;
      DeleteOurPending("pozisyon acildi");
      g_signal_count++;
      RefreshDailyCounters();
      DrawSignalArrow(g_signal_time, g_signal_high, g_signal_low, side);
      g_state       = ST_POSITION;
      g_last_action = StringFormat("%s bekleyen emir doldu", SideName(side));
      PrintFormat("GIRIS (bekleyen emir doldu): yon=%s | plan SL=%.*f TP=%.*f",
                  SideName(side), _Digits, g_planned_sl, _Digits, g_planned_tp);
      return;
     }
   if(CountOurPending() == 0)
      ResetSetup("bekleyen emirler iptal/expire oldu");
  }

void ProcessBounceMode(const MqlRates &rates[], const double &atr[])
  {
   if(ArraySize(rates) < 60)
      return;
   double atr1 = (ArraySize(atr) > 1 ? atr[1] : 0.0);
   if(atr1 <= 0.0)
     {
      g_last_action = "ATR verisi hazir degil";
      return;
     }

   double close1 = rates[1].close;
   g_current_trend = CalcTrend(close1);

   BuildZoneSets(rates, atr1, close1);
   DrawZones();

   if(CountOurPositions(0) > 0)
     {
      if(g_state == ST_PENDING)
        {
         int side = g_side;
         DeleteOurPending("pozisyon acildi");
         g_signal_count++;
         RefreshDailyCounters();
         DrawSignalArrow(g_signal_time, g_signal_high, g_signal_low, side);
         g_state = ST_POSITION;
         g_last_action = StringFormat("%s bekleyen emir doldu", SideName(side));
        }
      return;
     }
   if(g_state == ST_POSITION)
     {
      ResetSetupValues();
      g_last_action = "Pozisyon kapandi, yeni S/R kurulumu araniyor";
      return;
     }

   if(g_state != ST_IDLE)
     {
      g_bars_since_touch++;
      if(InpMaxWaitBars > 0 && g_bars_since_touch > InpMaxWaitBars)
        {
         ResetSetup("kurulum suresi doldu");
         return;
        }
     }

   switch(g_state)
     {
      case ST_IDLE:    TryArmSetup(rates, atr1, close1);   break;
      case ST_ARMED:   ProcessArmed(rates, atr1);          break;
      case ST_TOUCH:   ProcessFirstFractal(rates, atr1);   break;
      case ST_PENDING: ProcessPending(rates, atr1, close1); break;
      default:         ResetSetupValues();                 break;
     }
  }

//+------------------------------------------------------------------+
//| Tick duzeyinde cikislar (para / sure / BE)                       |
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
      if(InpMoveToBEAtRR > 0.0 && g_planned_entry > 0.0 && g_planned_sl > 0.0 && side != 0)
        {
         double risk = MathAbs(g_planned_entry - g_planned_sl);
         if(risk > 0.0)
           {
            double cur_price = (side > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                        : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
            double moved = side * (cur_price - g_planned_entry);
            if(moved >= InpMoveToBEAtRR * risk)
              {
               double cur_sl = PositionGetDouble(POSITION_SL);
               bool need_move = (side > 0 && (cur_sl <= 0.0 || cur_sl < g_planned_entry)) ||
                                (side < 0 && (cur_sl <= 0.0 || cur_sl > g_planned_entry));
               if(need_move)
                 {
                  double be_sl  = NormalizePriceToTick(g_planned_entry, (side > 0 ? 1 : -1));
                  double cur_tp = PositionGetDouble(POSITION_TP);
                  if(trade.PositionModify(ticket, be_sl, cur_tp))
                     PrintFormat("SL BE'ye cekildi: ticket=%I64u", ticket);
                 }
              }
           }
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

   string sup_text = (g_sup_ok
                      ? StringFormat("%.*f..%.*f (temas %d%s)", _Digits, g_sup.bottom,
                                     _Digits, g_sup.top, g_sup.touches,
                                     (g_sup.round_level ? ", yuvarlak" : ""))
                      : "yok");
   string res_text = (g_res_ok
                      ? StringFormat("%.*f..%.*f (temas %d%s)", _Digits, g_res.bottom,
                                     _Digits, g_res.top, g_res.touches,
                                     (g_res.round_level ? ", yuvarlak" : ""))
                      : "yok");
   string setup_text;
   if(g_side == 0)
      setup_text = "yok";
   else
      setup_text = StringFormat("%s | bolge %.*f..%.*f | temas %d",
                                SideName(g_side), _Digits, g_zone.bottom,
                                _Digits, g_zone.top, g_zone_touches);

   Comment("S/R BOUNCE ROBOT v1.00\n",
           "Sembol: ", _Symbol, " | TF: ", EnumToString(g_tf),
           " | spread: ", DoubleToString((SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                                          SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point, 0),
           " point\n",
           "Yontem: ", MethodName(),
           " | trend: ", TrendName(g_current_trend),
           " (EMA ", IntegerToString(InpTrendFastEMA), "/", IntegerToString(InpTrendSlowEMA), ")",
           " | ATR=", DoubleToString(atr1, _Digits), "\n",
           "Destek: ", sup_text, "\n",
           "Direnc: ", res_text, "\n",
           "Durum: ", StateName(), "\n",
           "Kurulum: ", setup_text, "\n",
           "Bekleyen emir: ", IntegerToString(CountOurPending()),
           " | acik pozisyon B/S: ", IntegerToString(CountOurPositions(1)), "/",
           IntegerToString(CountOurPositions(-1)),
           " | sinyal: ", IntegerToString(g_signal_count),
           " | atlanan: ", IntegerToString(g_skip_count),
           " | bugun: ", IntegerToString(g_trades_today), "\n",
           "Son islem: ", g_last_action);
  }

//+------------------------------------------------------------------+
//| Kapanmis mum isleme                                              |
//+------------------------------------------------------------------+
void ProcessClosedBar()
  {
   int needed = (int)MathMax(120, MathMax(InpLookbackBars + 60,
                                           InpTrendSlowEMA * 3 + 30));
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, g_tf, 0, needed, rates);
   if(copied < 60)
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
      PrintFormat("BOUNCE[%s] trend=%s durum=%s S=%s R=%s",
                  TimeToString(rates[1].time, TIME_DATE | TIME_MINUTES),
                  TrendName(g_current_trend), StateName(),
                  (g_sup_ok ? DoubleToString(g_sup.price, _Digits) : "-"),
                  (g_res_ok ? DoubleToString(g_res.price, _Digits) : "-"));

   ProcessBounceMode(rates, atr);
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
   if(InpLookbackBars < 50 || InpPivotStrength < 1 || InpPivotStrength > 5 ||
      InpFractalStrength < 1 || InpFractalStrength > 5)
     {
      Print("Hatali girdiler: bakis >= 50, pivot/fractal mum sayisi 1-5 olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMinTouches < 2 || InpStrongZoneTouches < InpMinTouches)
     {
      Print("Hatali girdiler: min. temas >= 2 ve guclu bolge esigi >= min. temas olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpZoneToleranceATR <= 0.0 || InpApproachATR <= 0.0 ||
      !MathIsValidNumber(InpZoneToleranceATR) || !MathIsValidNumber(InpApproachATR))
     {
      Print("Hatali girdiler: bolge toleransi ve yaklasim mesafesi pozitif olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpPinWickRatio < 1.0 || !MathIsValidNumber(InpPinWickRatio))
     {
      Print("Hatali girdiler: pin bar fitil/govde orani >= 1.0 olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!InpUsePinBar && !InpUseEngulfing && InpEntryMethod == BOUNCE_CONFIRMATION)
     {
      Print("Hatali girdiler: mum onayi icin en az bir kalip (pin bar / engulfing) acik olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpFractalBufferPips < 1 || InpFractalAwayPips < 1)
     {
      Print("Hatali girdiler: fractal tamponu ve mesafesi >= 1 pip olmali (makale: 6-20 pip).");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpFractalBufferPips < 6 || InpFractalBufferPips > 20)
      Print("BILGI: fractal tamponu makalenin 6-20 pip araligi disinda; tester ile dogrulayin.");
   if(InpSLBufferATR < 0.0 || InpSLBufferPoints < 0 || InpTPOffsetPoints < 0 ||
      InpFallbackTP_RR <= 0.0 || InpMinRR < 0.0 || InpMinTargetATR < 0.0 ||
      !MathIsValidNumber(InpFallbackTP_RR))
     {
      Print("Hatali girdiler: SL/TP parametreleri gecersiz (negatif olamaz, carpan > 0).");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLotSize <= 0.0 || !MathIsValidNumber(InpLotSize) ||
      InpRiskPercent <= 0.0 || !MathIsValidNumber(InpRiskPercent))
     {
      Print("Hatali girdiler: lot ve risk % pozitif olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMaxOpenPositions < 0 || InpDeviationPoints < 0 || InpMaxSpreadPoints < 0 ||
      InpDirectOffsetPoints < 0 || InpPendingExpireMinutes < 0 ||
      InpMaxWaitBars < 0 || InpConfirmMaxBarsAfterTouch < 0 ||
      InpMaxPositionMinutes < 0 || InpMaxTradesPerDay < 0 || InpRoundStepPips < 0)
     {
      Print("Hatali girdiler: sayisal ayarlar negatif olamaz.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMoneyTakeProfit < 0.0 || InpMoneyStopLoss < 0.0 || InpMaxDailyLoss < 0.0 ||
      InpMaxSL_ATR < 0.0 || InpMoveToBEAtRR < 0.0)
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

   g_object_prefix = StringFormat("BOUNCE_%d_%s_%s_",
                                  InpMagicNumber, _Symbol, EnumToString(g_tf));
   g_last_bar_time = iTime(_Symbol, g_tf, 0);
   RefreshDailyCounters();
   ResetSetupValues();

   EventSetTimer(1);

   PrintFormat("BOUNCE ROBOT hazir: %s TF=%s | yontem=%s | bolge: bakis=%d pivot=%d temas>=%d tol=%.2f ATR",
               _Symbol, EnumToString(g_tf), MethodName(), InpLookbackBars,
               InpPivotStrength, InpMinTouches, InpZoneToleranceATR);
   string risk_txt = (InpUseRiskPercent ? DoubleToString(InpRiskPercent, 1) : "KAPALI");
   PrintFormat("Risk: lot=%.2f risk=%s | SL tampon=%.2f ATR | TP=karsi S/R (yoksa x%.1f R) | magic=%d",
               InpLotSize, risk_txt, InpSLBufferATR, InpFallbackTP_RR, InpMagicNumber);
   Print("Sinyaller yalnizca KAPANMIS mumlarda degerlendirilir. Acilista gecmise donuk islem acilmaz.");
   Print("Akis: S/R bolgesi -> yaklasim -> (dogrudan / mum onayi / iki fractal) -> giris -> karsi bolgede TP");

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
   CheckPendingFills();
   CheckTickExits();
   UpdatePanel();
  }

void OnTimer()
  {
   CheckNewBar();
   CheckPendingFills();
   CheckTickExits();
   UpdatePanel();
  }

double OnTester()
  {
   // Strategy Tester optimizasyonunda net kari sirala.
   return TesterStatistics(STAT_PROFIT);
  }
//+------------------------------------------------------------------+
