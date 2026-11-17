//+------------------------------------------------------------------+
//|                                          AO_TwinPeaks_Bot.mq5    |
//|  Bill Williams AWESOME OSCILLATOR - MT5 ROBOT (EA) - Tam Otomatik|
//|                                                                  |
//|  Kaynak: Trading Strategy Guides - "Bill Williams Awesome       |
//|  Oscillator Strategy - Big Profits, Small Losses"                |
//|  https://tradingstrategyguides.com/bill-williams-awesome-oscillator-strategy/|
//|                                                                  |
//|  Bu bir UZMAN DANISMAN (robot) dosyasidir; gosterge degildir.    |
//|  Grafige eklenir, sinyal geldiginde emir acar/kapatir.           |
//|  Manuel mudahale gerekmez; tum kararlar KAPANMIS mumlarda alinir.|
//|                                                                  |
//|  Gosterge:  AO = SMA((H+L)/2, 5) - SMA((H+L)/2, 34)              |
//|  AO rengi:  bar onceki bardan yuksekse YESIL, dusukse KIRMIZI    |
//|             (MT5 histogram renk mantigi ile ayni)                |
//|                                                                  |
//|  MAKALENIN ALIM KURALLARI (6 adim; SATIM tam tersi):             |
//|   1) AO sifir cizgisinin ALTINDA olmali.                        |
//|   2) AO histograminda ardisik IKI dip; IKINCI dip daha YUKSEK    |
//|      olmali (Twin Peaks / bozulma).                              |
//|   3) Ikinci dipten hemen sonra AO YESIL bara donmeli.            |
//|   4) AO sifir cizgisini YUKARI kirinca piyasa fiyatindan AL.     |
//|   5) SL = en son fiyat swing dibinin ALTINA (makale: tampon      |
//|      YOK; dip kirilirsa desen gecersiz olur).                    |
//|   6) TP = AO ardisik IKI KIRMIZI bar bastiginda pozisyonu kapat. |
//|                                                                  |
//|  Makalenin diger AO sinyalleri de (secilebilir mod olarak) var:   |
//|   * SAUCER (tabak): 2 ardisik kirmizi bar + 3. bar yesil ve      |
//|     daha yuksek (sifir ustunde) -> LONG; tersi SHORT.            |
//|   * ZERO CROSS: AO sifiri yukari/asagi kesince giris.            |
//|                                                                  |
//|  TASARIM KARARLARI (makalede oznel kalan noktalar - ayrintili    |
//|  aciklama README_AO_Bot.md icinde):                              |
//|   * "Ardisik iki swing dip" = AO histograminda InpAOPivotStrength |
//|     kadar bar saga/sola ekstrem olan iki dip; ikincisi daha       |
//|     yuksek ve ikisi de sifirin altinda.                          |
//|   * "Hemen yesil bar" = pivot tanimi geregi 2. dibi izleyen bar   |
//|     yukseliyor (AO[i-1] > AO[i]).                                |
//|   * "Sifir cizgisi kirilimi" = onceki bar <= 0 ve son kapanmis     |
//|     bar > 0. Giris, bu bar kapanisindan sonraki ilk tick'te.      |
//|   * "SL: son swing dibi" = 2. AO dibinin barindaki fiyat         |
//|     araliginin en dusuk diplerinden biri (InpSLSwingBars kadar    |
//|     sag/sol), InpSLBufferPoints tamponla (vars. 0 = makale).      |
//|   * "TP: iki kirmizi bar" = AO[1] < AO[2] < AO[3] (LONG icin).     |
//|     Sabit TP istenirse InpUseFixedTP + InpFixedTP_RR.             |
//|   * AO periyotlari InpAOFastPeriod/InpAOSlowPeriod ile             |
//|     degistirilebilir (varsayilan 5 / 34 = makale).                |
//|                                                                  |
//|  GUVENLIK: Sinyaller YALNIZCA KAPANMIS mumlarda degerlendirilir. |
//|  Tek pozisyon (varsayilan), spread filtresi, risk % lot hesabi,  |
//|  gunluk limit, islem saatleri, para/sure/BE cikislari dahildir.   |
//|  Once Strategy Tester'da test edin. Yatirim tavsiyesi degildir.   |
//+------------------------------------------------------------------+
#property copyright "Bill Williams AO Twin Peaks - MT5 Robot"
#property version   "1.00"
#property strict
#property description "Awesome Oscillator (Twin Peaks / Saucer / Zero Cross) tam otomatik MT5 robotu"
#property description "AO = SMA(median,5) - SMA(median,34); giris: twin peaks + sifir cizgisi kirilimi"
#property description "SL: son swing dibi/tepesi | TP: ardisik iki ters renkli AO bari"
#property description "Sinyaller yalnizca kapanmis mumlarda degerlendirilir"

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Tipler                                                           |
//+------------------------------------------------------------------+
enum ENUM_AO_MODE
  {
   AO_TWIN_PEAKS = 0, // Twin Peaks + sifir cizgisi (makalenin 6 adimi)
   AO_SAUCER     = 1, // Saucer (tabak) sinyali
   AO_ZERO_CROSS = 2  // Sadece sifir cizgisi kirilimi
  };

//+------------------------------------------------------------------+
//| Girdiler                                                         |
//+------------------------------------------------------------------+
enum ENUM_TRADE_MODE
  {
   TRADE_MODE_NORMAL  = 0,   // Sadece DUZ islem
   TRADE_MODE_REVERSE = 1,   // Sadece TERS islem
   TRADE_MODE_BOTH    = 2    // DUZ + TERS ayni anda (ayri magic)
  };

input group "1) Awesome Oscillator ve desen"
input ENUM_TIMEFRAMES InpTimeframe        = PERIOD_CURRENT; // Islem zaman dilimi (0 = grafik TF)
input ENUM_AO_MODE    InpMode             = AO_TWIN_PEAKS;  // Strateji modu
input int             InpAOFastPeriod     = 5;    // AO hizli SMA periyodu (makale: 5)
input int             InpAOSlowPeriod     = 34;   // AO yavas SMA periyodu (makale: 34)
input int             InpAOPivotStrength  = 2;    // AO swing dip/tepe icin mum sayisi (her iki yan)
input int             InpPatternLookbackBars = 60;   // Twin Peaks tarama penceresi (mum)
input int             InpMaxPatternAgeBars = 30;  // 2. dip en fazla kac bar once olmali (0 = sinirsiz)
input bool            InpRequireZeroCross = true; // Giris icin sifir cizgisi kirilimi sart (makale Adim 4)

input group "2) Cikis kurallari (makale Adim 5-6)"
input bool            InpUseIndicatorExit = true; // AO iki ardisik ters renkli barda kapat (TP)
input bool            InpExitOnOppositeZeroCross = false; // Ters sifir kiriliminda da kapat
input bool            InpUseFixedTP       = false; // Sabit (R/R) TP kullan
input double          InpFixedTP_RR       = 2.0;   // Sabit TP = risk x bu carpan
input int             InpSLSwingBars      = 2;     // SL swing penceresi (AO dibi cevresi)
input int             InpSLBufferPoints   = 0;     // SL tamponu (point, makale: 0)
input int             InpSLSwingLookbackBars = 10; // Saucer/Zero Cross icin SL swing penceresi

input group "3) Pozisyon ve risk"
input double          InpLotSize          = 0.01; // Sabit lot
input bool            InpUseRiskPercent   = false; // Risk % ile lot hesabi
input double          InpRiskPercent      = 1.0;  // Islem basina risk (%)
input int             InpMagicNumber      = 20261119; // Magic number
input int             InpDeviationPoints  = 20;   // Maksimum sapma (point)
input int             InpMaxSpreadPoints  = 0;    // Maksimum spread (point) - 0 = kapali
input int             InpMaxOpenPositions = 1;    // Maksimum acik pozisyon (0 = sinirsiz)
input bool            InpAllowLongs       = true; // LONG islemler acik
input bool            InpAllowShorts      = true; // SHORT islemler acik
input ENUM_TRADE_MODE InpTradeMode        = TRADE_MODE_NORMAL; // Islem modu: 0=duz 1=ters 2=duz+ters (ayri magic)
input int             InpMagicMirror       = 0;    // Ters islem magic (0 = InpMagicNumber+1)
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
input bool            InpDrawArrows      = true; // Sinyal oklarini ciz
input bool            InpShowPanel       = true; // Bilgi panelini goster
input bool            InpDeleteOnExit    = true; // EA kaldirilinca grafik nesnelerini sil
input bool            InpLogSignals      = false; // Her mumda detayli log

//+------------------------------------------------------------------+
//| Globaller                                                        |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES g_tf = PERIOD_CURRENT;

int      g_fast_handle = INVALID_HANDLE;
int      g_slow_handle = INVALID_HANDLE;
int      g_atr_handle  = INVALID_HANDLE;
datetime g_last_bar_time = 0;

double   g_ao_last        = 0.0;   // son kapanmis AO degeri
int      g_ao_color       = 0;     // +1 yesil, -1 kirmizi, 0 notr
bool     g_bull_pattern   = false;
bool     g_bear_pattern   = false;
int      g_pattern_age    = -1;
double   g_pattern_low    = 0.0;   // 2. AO dip degeri (bilgi)
double   g_pattern_high   = 0.0;   // 2. AO tepe degeri (bilgi)

double   g_planned_entry[2] = {0.0, 0.0};   // [0]=duz, [1]=ters
double   g_planned_sl[2]    = {0.0, 0.0};
double   g_planned_tp[2]    = {0.0, 0.0};

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

string ModeName()
  {
   switch(InpMode)
     {
      case AO_SAUCER:     return "SAUCER (tabak)";
      case AO_ZERO_CROSS: return "ZERO CROSS";
      default:            return "TWIN PEAKS";
     }
  }

string ColorName(const int c)
  {
   if(c > 0)
      return "YESIL";
   if(c < 0)
      return "KIRMIZI";
   return "NOTR";
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
//+------------------------------------------------------------------+
//| Islem modu yardimcilari (duz / ters / ikisi birlikte)            |
//+------------------------------------------------------------------+
ulong g_magic_main   = 0;
ulong g_magic_mirror = 0;

bool ModeNormalOn()  { return (InpTradeMode == TRADE_MODE_NORMAL || InpTradeMode == TRADE_MODE_BOTH); }
bool ModeReverseOn() { return (InpTradeMode == TRADE_MODE_REVERSE || InpTradeMode == TRADE_MODE_BOTH); }
bool ModeBothOn()    { return (InpTradeMode == TRADE_MODE_BOTH); }

ulong MagicOfMode(const int mode)
  {
   if(mode == 1 && ModeBothOn())
      return g_magic_mirror;
   return g_magic_main;
  }

int ModeOfMagic(const ulong magic)
  {
   if(g_magic_mirror != g_magic_main && magic == g_magic_mirror)
      return 1;
   // Sadece TERS modunda tum emirler ana magic ile acilir -> plan indeksi 1
   if(!ModeNormalOn() && ModeReverseOn())
      return 1;
   return 0;
  }

bool IsOurMagic(const ulong magic)
  {
   return (magic == g_magic_main || magic == g_magic_mirror);
  }

string ModeText()
  {
   if(ModeBothOn())
      return "DUZ+TERS";
   if(ModeReverseOn())
      return "TERS";
   return "DUZ";
  }

bool SelectOurPosition(const ulong ticket)
  {
   if(ticket == 0)
      return false;
   if(!PositionSelectByTicket(ticket))
      return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;
   if(!IsOurMagic((ulong)PositionGetInteger(POSITION_MAGIC)))
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
//| Gosterge: AO ve ATR                                              |
//+------------------------------------------------------------------+
// AO = SMA(median, fast) - SMA(median, slow); median = (H+L)/2
bool GetAOSeries(const int count, double &ao[])
  {
   if(g_fast_handle == INVALID_HANDLE || g_slow_handle == INVALID_HANDLE)
      return false;
   if(count < 6)
      return false;
   double fast[], slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   if(CopyBuffer(g_fast_handle, 0, 0, count, fast) != count)
      return false;
   if(CopyBuffer(g_slow_handle, 0, 0, count, slow) != count)
      return false;
   ArrayResize(ao, count);
   for(int i = 0; i < count; i++)
      ao[i] = fast[i] - slow[i];
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

// AO bar rengi: onceki bardan yuksekse yesil (+1), dusukse kirmizi (-1)
int AOColor(const double &ao[], const int idx)
  {
   if(idx + 1 >= ArraySize(ao))
      return 0;
   if(ao[idx] > ao[idx + 1])
      return 1;
   if(ao[idx] < ao[idx + 1])
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
      if(!IsOurMagic((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC)))
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

//+------------------------------------------------------------------+
//| AO desenleri                                                     |
//+------------------------------------------------------------------+
bool IsAOPivotLow(const double &ao[], const int idx, const int strength)
  {
   int n = ArraySize(ao);
   if(idx - strength < 1)
      return false;
   if(idx + strength >= n)
      return false;
   double v = ao[idx];
   for(int k = 1; k <= strength; k++)
     {
      if(ao[idx - k] <= v)
         return false;
      if(ao[idx + k] <= v)
         return false;
     }
   return true;
  }

bool IsAOPivotHigh(const double &ao[], const int idx, const int strength)
  {
   int n = ArraySize(ao);
   if(idx - strength < 1)
      return false;
   if(idx + strength >= n)
      return false;
   double v = ao[idx];
   for(int k = 1; k <= strength; k++)
     {
      if(ao[idx - k] >= v)
         return false;
      if(ao[idx + k] >= v)
         return false;
     }
   return true;
  }

// Makale Adim 1-3: AO sifir altinda + ardisik iki dip (ikincisi daha yuksek)
// + ikinci dipten sonra yesil bar. second_idx = 2. AO dibinin bar indeksi.
bool DetectBullishTwinPeaks(const double &ao[], int &second_idx)
  {
   int n = ArraySize(ao);
   int strength = InpAOPivotStrength;
   int limit = MathMin(InpPatternLookbackBars, n - strength - 1);
   if(limit <= strength + 1)
      return false;

   int newer = -1, older = -1;
   for(int i = strength + 1; i <= limit; i++)
     {
      if(!IsAOPivotLow(ao, i, strength))
         continue;
      if(ao[i] >= 0.0)                    // desen sifir cizgisinin altinda
         continue;
      if(newer < 0)
        {
         newer = i;
         continue;
        }
      older = i;
      break;
     }
   if(newer < 0 || older < 0)
      return false;
   if(ao[newer] <= ao[older])             // ikinci dip daha yuksek olmali
      return false;
   if(InpMaxPatternAgeBars > 0 && (newer - 1) > InpMaxPatternAgeBars)
      return false;
   if(!(ao[newer - 1] > ao[newer]))       // dipten sonra yesil bar
      return false;
   second_idx = newer;
   return true;
  }

// Makale (tersi): AO sifir ustunde + ardisik iki tepe (ikincisi daha dusuk)
bool DetectBearishTwinPeaks(const double &ao[], int &second_idx)
  {
   int n = ArraySize(ao);
   int strength = InpAOPivotStrength;
   int limit = MathMin(InpPatternLookbackBars, n - strength - 1);
   if(limit <= strength + 1)
      return false;

   int newer = -1, older = -1;
   for(int i = strength + 1; i <= limit; i++)
     {
      if(!IsAOPivotHigh(ao, i, strength))
         continue;
      if(ao[i] <= 0.0)
         continue;
      if(newer < 0)
        {
         newer = i;
         continue;
        }
      older = i;
      break;
     }
   if(newer < 0 || older < 0)
      return false;
   if(ao[newer] >= ao[older])             // ikinci tepe daha dusuk olmali
      return false;
   if(InpMaxPatternAgeBars > 0 && (newer - 1) > InpMaxPatternAgeBars)
      return false;
   if(!(ao[newer - 1] < ao[newer]))       // tepeden sonra kirmizi bar
      return false;
   second_idx = newer;
   return true;
  }

// Saucer (tabak) - boga: sifir ustunde 2 kirmizi bar, sonra yesil ve daha yuksek
bool BullishSaucer(const double &ao[])
  {
   if(ArraySize(ao) < 6)
      return false;
   if(ao[1] <= 0.0 || ao[2] <= 0.0 || ao[3] <= 0.0)
      return false;
   if(!(ao[2] < ao[3] && ao[3] < ao[4]))  // 2 ardisik kirmizi bar
      return false;
   if(!(ao[1] > ao[2]))                   // 3. bar yesil ve daha yuksek
      return false;
   return true;
  }

// Saucer - ayi: sifir altinda 2 yesil bar, sonra kirmizi ve daha dusuk
bool BearishSaucer(const double &ao[])
  {
   if(ArraySize(ao) < 6)
      return false;
   if(ao[1] >= 0.0 || ao[2] >= 0.0 || ao[3] >= 0.0)
      return false;
   if(!(ao[2] > ao[3] && ao[3] > ao[4]))
      return false;
   if(!(ao[1] < ao[2]))
      return false;
   return true;
  }

//+------------------------------------------------------------------+
//| SL: fiyat swing dibi/tepesi                                      |
//+------------------------------------------------------------------+
// AO 2. dibinin barindaki fiyat araliginin en dusuk dibi (makale Adim 5)
double PriceSwingLowAt(const MqlRates &rates[], const int pivot_bar, const int swing_bars)
  {
   int n = ArraySize(rates);
   int from = MathMax(1, pivot_bar - swing_bars - 1);
   int to   = MathMin(n - 1, pivot_bar + swing_bars);
   double low = rates[from].low;
   for(int i = from; i <= to; i++)
      low = MathMin(low, rates[i].low);
   return low;
  }

double PriceSwingHighAt(const MqlRates &rates[], const int pivot_bar, const int swing_bars)
  {
   int n = ArraySize(rates);
   int from = MathMax(1, pivot_bar - swing_bars - 1);
   int to   = MathMin(n - 1, pivot_bar + swing_bars);
   double high = rates[from].high;
   for(int i = from; i <= to; i++)
      high = MathMax(high, rates[i].high);
   return high;
  }

double RecentSwingLow(const MqlRates &rates[], const int lookback)
  {
   int n = ArraySize(rates);
   int to = MathMin(n - 1, MathMax(2, lookback));
   double low = rates[1].low;
   for(int i = 1; i <= to; i++)
      low = MathMin(low, rates[i].low);
   return low;
  }

double RecentSwingHigh(const MqlRates &rates[], const int lookback)
  {
   int n = ArraySize(rates);
   int to = MathMin(n - 1, MathMax(2, lookback));
   double high = rates[1].high;
   for(int i = 1; i <= to; i++)
      high = MathMax(high, rates[i].high);
   return high;
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
//| Grafik                                                           |
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

//+------------------------------------------------------------------+
//| Emir acma                                                        |
//+------------------------------------------------------------------+
// Tek bir emir gonderir (mode: 0 = duz magic, 1 = ters magic)
bool SendEntry(const int side, const double entry, const double entry_sl, const double entry_tp,
               const double atr1, const int mode, const string signal_text,
               const datetime signal_time, const double sig_high, const double sig_low)
  {
   double sl = entry_sl;
   double tp = entry_tp;

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
   int open_cnt = (ModeBothOn() ? CountOurPositions(side) : CountOurPositions(0));
   if(InpMaxOpenPositions > 0 && open_cnt >= InpMaxOpenPositions)
     {
      g_skip_count++;
      g_last_action = StringFormat("%s yonunde maksimum pozisyon sayisina ulasildi", SideName(side));
      return false;
     }
   if(side > 0 && sl >= entry)
     {
      g_skip_count++;
      g_last_action = "SL giris uzerinde kaldi, islem atlandi";
      return false;
     }
   if(side < 0 && sl <= entry)
     {
      g_skip_count++;
      g_last_action = "SL giris altinda kaldi, islem atlandi";
      return false;
     }

   double risk = MathAbs(entry - sl);
   if(risk <= 0.0)
      return false;

   if(InpMaxSL_ATR > 0.0 && atr1 > 0.0 && risk > InpMaxSL_ATR * atr1)
     {
      g_skip_count++;
      g_last_action = StringFormat("SL cok genis (%.1f x ATR), islem atlandi", risk / atr1);
      PrintFormat("ATLANDI: SL %.1f x ATR | yon=%s", risk / atr1, SideName(side));
      return false;
     }

   long stops_level  = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_distance = MathMax((double)stops_level, (double)freeze_level) * _Point;
   if(risk < min_distance + TickSize())
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

   double volume = CalcLot(side, entry, sl);
   if(volume <= 0.0)
     {
      g_last_action = "Lot hacmi broker sinirlarina uymuyor";
      return false;
     }

   string comment = (side > 0 ? "AO BUY " : "AO SELL ");
   comment += (mode == 1 ? "T" : "D");

   trade.SetExpertMagicNumber(MagicOfMode(mode));
   bool sent = false;
   if(side > 0)
      sent = trade.Buy(volume, _Symbol, 0.0, sl, tp, comment);
   else
      sent = trade.Sell(volume, _Symbol, 0.0, sl, tp, comment);

   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Giris basarisiz (%s): %s | yon=%s lot=%.8f retcode=%u (%s)",
                  (mode == 1 ? "TERS" : "DUZ"), signal_text, SideName(side), volume,
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
      g_last_action = "Emir broker tarafindan reddedildi";
      return false;
     }

   DrawSignalArrow(signal_time, sig_high, sig_low, side);
   g_planned_entry[mode] = entry;
   g_planned_sl[mode]    = sl;
   g_planned_tp[mode]    = tp;
   PrintFormat("GIRIS (%s): %s | yon=%s | sinyal mumu=%s | lot=%.8f | fiyat=%.*f | SL=%.*f | TP=%s | magic=%I64u",
               (mode == 1 ? "TERS" : "DUZ"), signal_text, SideName(side), TimeToString(signal_time), volume,
               _Digits, entry, _Digits, sl,
               (tp > 0.0 ? DoubleToString(tp, _Digits) : "AO cikisi"), MagicOfMode(mode));
   g_last_action = StringFormat("%s %s islem acildi (%s)", SideName(side),
                                (mode == 1 ? "ters" : "duz"), signal_text);
   return true;
  }

//+------------------------------------------------------------------+
//| Sinyal girisi: duz ve/veya ters emirleri acar                    |
//+------------------------------------------------------------------+
bool OpenSignal(const int side, const double sl_ref, const double atr1,
                const string signal_text, const datetime signal_time,
                const double sig_high, const double sig_low)
  {
   if(side == 0)
      return false;
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

   // --- DUZ yon plani ---
   double entry   = (side > 0 ? tick.ask : tick.bid);
   double buffer  = InpSLBufferPoints * _Point;
   double sl      = NormalizePriceToTick(sl_ref - side * buffer, (side > 0 ? -1 : 1));
   double tp      = 0.0;
   if(InpUseFixedTP)
      tp = NormalizePriceToTick(entry + side * InpFixedTP_RR * MathAbs(entry - sl),
                                (side > 0 ? -1 : 1));

   bool any = false;

   if(ModeNormalOn())
      any = SendEntry(side, entry, sl, tp, atr1, 0, signal_text, signal_time, sig_high, sig_low) || any;

   // --- TERS yon plani: yon cevrilir, SL/TP mesafeleri yer degistirir ---
   if(ModeReverseOn())
     {
      int    rside  = -side;
      double rentry = (rside > 0 ? tick.ask : tick.bid);
      double d_sl = (sl > 0.0 ? MathAbs(entry - sl) : 0.0);
      double d_tp = (tp > 0.0 ? MathAbs(tp - entry) : 0.0);
      double rsl = 0.0, rtp = 0.0;
      if(d_sl > 0.0 || d_tp > 0.0)
        {
         double new_sl_dist = (d_tp > 0.0 ? d_tp : d_sl);
         rsl = NormalizePriceToTick(rentry - rside * new_sl_dist, (rside > 0 ? -1 : 1));
         if(d_sl > 0.0 && d_tp > 0.0)
            rtp = NormalizePriceToTick(rentry + rside * d_sl, (rside > 0 ? -1 : 1));
        }
      any = SendEntry(rside, rentry, rsl, rtp, atr1, 1, signal_text, signal_time, sig_high, sig_low) || any;
     }

   if(!any)
      return false;

   g_signal_count++;
   RefreshDailyCounters();
   return true;
  }

//+------------------------------------------------------------------+
//| AO tabanli cikislar (makale Adim 6)                              |
//+------------------------------------------------------------------+
void ManagePositionsByAO(const double &ao[])
  {
   if(ArraySize(ao) < 5)
      return;
   if(CountOurPositions(0) == 0)
      return;
   double a1 = ao[1], a2 = ao[2], a3 = ao[3];
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
      if(side == 0)
         continue;
      if(InpUseIndicatorExit)
        {
         // LONG: iki ardisik kirmizi bar -> TP
         if(side > 0 && a1 < a2 && a2 < a3)
           {
            CloseOurPosition(ticket, "AO iki kirmizi bar (TP)");
            continue;
           }
         // SHORT: iki ardisik yesil bar -> TP
         if(side < 0 && a1 > a2 && a2 > a3)
           {
            CloseOurPosition(ticket, "AO iki yesil bar (TP)");
            continue;
           }
        }
      if(InpExitOnOppositeZeroCross)
        {
         if(side > 0 && a1 < 0.0 && a2 >= 0.0)
           {
            CloseOurPosition(ticket, "AO sifiri asagi kesti");
            continue;
           }
         if(side < 0 && a1 > 0.0 && a2 <= 0.0)
           {
            CloseOurPosition(ticket, "AO sifiri yukari kesti");
            continue;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Sinyal uretimi                                                   |
//+------------------------------------------------------------------+
void ProcessAOSignals(const MqlRates &rates[], const double &ao[], const double atr1)
  {
   double sig_high = rates[1].high;
   double sig_low  = rates[1].low;
   datetime sig_time = rates[1].time;

   // --- Ortak: sifir cizgisi kirilimi ---
   bool cross_up   = (ao[1] > 0.0 && ao[2] <= 0.0);
   bool cross_down = (ao[1] < 0.0 && ao[2] >= 0.0);

   if(InpMode == AO_ZERO_CROSS)
     {
      if(cross_up)
        {
         double sl_ref = RecentSwingLow(rates, InpSLSwingLookbackBars);
         OpenSignal(1, sl_ref, atr1, "AO sifir cizgisi yukari",
                   sig_time, sig_high, sig_low);
         return;
        }
      if(cross_down)
        {
         double sl_ref = RecentSwingHigh(rates, InpSLSwingLookbackBars);
         OpenSignal(-1, sl_ref, atr1, "AO sifir cizgisi asagi",
                    sig_time, sig_high, sig_low);
         return;
        }
      g_last_action = "AO sifir cizgisi kirilimi bekleniyor";
      return;
     }

   if(InpMode == AO_SAUCER)
     {
      if(BullishSaucer(ao))
        {
         double sl_ref = RecentSwingLow(rates, InpSLSwingLookbackBars);
         OpenSignal(1, sl_ref, atr1, "AO saucer (tabak)",
                    sig_time, sig_high, sig_low);
         return;
        }
      if(BearishSaucer(ao))
        {
         double sl_ref = RecentSwingHigh(rates, InpSLSwingLookbackBars);
         OpenSignal(-1, sl_ref, atr1, "AO saucer (tabak)",
                    sig_time, sig_high, sig_low);
         return;
        }
      g_last_action = "AO saucer deseni bekleniyor";
      return;
     }

   // --- TWIN PEAKS (makalenin 6 adimi) ---
   int bull_idx = 0, bear_idx = 0;
   bool bull = DetectBullishTwinPeaks(ao, bull_idx);
   bool bear = DetectBearishTwinPeaks(ao, bear_idx);
   g_bull_pattern = bull;
   g_bear_pattern = bear;

   if(bull)
     {
      g_pattern_age  = bull_idx - 1;
      g_pattern_low  = ao[bull_idx];
      g_pattern_high = 0.0;
     }
   else if(bear)
     {
      g_pattern_age  = bear_idx - 1;
      g_pattern_high = ao[bear_idx];
      g_pattern_low  = 0.0;
     }
   else
     {
      g_pattern_age  = -1;
      g_pattern_low  = 0.0;
      g_pattern_high = 0.0;
     }

   // Adim 4: sifir cizgisi kirilimi (veya istenirse daha erken giris)
   if(bull)
     {
      bool trigger = (InpRequireZeroCross ? cross_up : AOColor(ao, 1) > 0);
      if(trigger)
        {
         double sl_ref = PriceSwingLowAt(rates, bull_idx, InpSLSwingBars);
         OpenSignal(1, sl_ref, atr1, "AO Twin Peaks + sifir kirilimi",
                    sig_time, sig_high, sig_low);
         return;
        }
      g_last_action = StringFormat("Twin Peaks hazir (%d bar once), sifir kirilimi bekleniyor",
                                   bull_idx - 1);
      return;
     }
   if(bear)
     {
      bool trigger = (InpRequireZeroCross ? cross_down : AOColor(ao, 1) < 0);
      if(trigger)
        {
         double sl_ref = PriceSwingHighAt(rates, bear_idx, InpSLSwingBars);
         OpenSignal(-1, sl_ref, atr1, "AO Twin Peaks + sifir kirilimi",
                    sig_time, sig_high, sig_low);
         return;
        }
      g_last_action = StringFormat("Twin Peaks hazir (%d bar once), sifir kirilimi bekleniyor",
                                   bear_idx - 1);
      return;
     }

   g_last_action = "AO Twin Peaks deseni bekleniyor";
  }

//+------------------------------------------------------------------+
//| Kapanmis mum isleme                                              |
//+------------------------------------------------------------------+
void ProcessClosedBar()
  {
   int needed = (int)MathMax(150, InpPatternLookbackBars + InpAOSlowPeriod + 60);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, g_tf, 0, needed, rates);
   if(copied < 60)
     {
      g_last_action = StringFormat("Yetersiz mum verisi: %d", copied);
      return;
     }

   double ao[];
   if(!GetAOSeries(needed, ao))
     {
      g_last_action = "AO verisi hazir degil";
      return;
     }
   if(ArraySize(ao) < InpAOSlowPeriod + 5)
     {
      g_last_action = "AO icin yetersiz gecmis";
      return;
     }

   double atr1 = 0.0;
   GetATR(1, atr1);

   g_ao_last  = ao[1];
   g_ao_color = AOColor(ao, 1);

   if(InpLogSignals)
      PrintFormat("AO[%s] deger=%.6f renk=%s mod=%s",
                  TimeToString(rates[1].time, TIME_DATE | TIME_MINUTES),
                  g_ao_last, ColorName(g_ao_color), ModeName());

   // 1) AO tabanli cikislar (Adim 6)
   ManagePositionsByAO(ao);

   // 2) Pozisyon aciksa yeni giris yok (tek pozisyon disiplini)
   if(CountOurPositions(0) > 0)
     {
      g_last_action = "Pozisyon acik, AO cikisi bekleniyor";
      return;
     }

   // 3) Sinyal uretimi
   ProcessAOSignals(rates, ao, atr1);
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
      int    pmode  = ModeOfMagic((ulong)PositionGetInteger(POSITION_MAGIC));
      double p_entry = g_planned_entry[pmode];
      double p_sl    = g_planned_sl[pmode];
      if(InpMoveToBEAtRR > 0.0 && p_entry > 0.0 && p_sl > 0.0 && side != 0)
        {
         double risk = MathAbs(p_entry - p_sl);
         if(risk > 0.0)
           {
            double cur_price = (side > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                        : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
            double moved = side * (cur_price - p_entry);
            if(moved >= InpMoveToBEAtRR * risk)
              {
               double cur_sl = PositionGetDouble(POSITION_SL);
               bool need_move = (side > 0 && (cur_sl <= 0.0 || cur_sl < p_entry)) ||
                                (side < 0 && (cur_sl <= 0.0 || cur_sl > p_entry));
               if(need_move)
                 {
                  double be_sl  = NormalizePriceToTick(p_entry, (side > 0 ? 1 : -1));
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

   string pattern_text = "yok";
   if(g_bull_pattern)
      pattern_text = StringFormat("BOGA (2. dip %.6f, %d bar once)", g_pattern_low, g_pattern_age);
   else if(g_bear_pattern)
      pattern_text = StringFormat("AYI (2. tepe %.6f, %d bar once)", g_pattern_high, g_pattern_age);

   Comment("AO TWIN PEAKS ROBOT v1.00  [MOD: ", ModeText(), "]", "\n",
           "Sembol: ", _Symbol, " | TF: ", EnumToString(g_tf),
           " | spread: ", DoubleToString((SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                                          SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point, 0),
           " point\n",
           "Mod: ", ModeName(), " | AO(", IntegerToString(InpAOFastPeriod), ",",
           IntegerToString(InpAOSlowPeriod), ") = ", DoubleToString(g_ao_last, 6),
           " | renk: ", ColorName(g_ao_color), "\n",
           "ATR=", DoubleToString(atr1, _Digits),
           " | sifir kirilimi sarti: ", (InpRequireZeroCross ? "ACIK" : "KAPALI"), "\n",
           "Desen: ", pattern_text, "\n",
           "Acik pozisyon B/S: ", IntegerToString(CountOurPositions(1)), "/",
           IntegerToString(CountOurPositions(-1)),
           " | sinyal: ", IntegerToString(g_signal_count),
           " | atlanan: ", IntegerToString(g_skip_count),
           " | bugun: ", IntegerToString(g_trades_today), "\n",
           "Cikis: ", (InpUseIndicatorExit ? "AO iki ters renkli bar" : "kapali"),
           (InpUseFixedTP ? StringFormat(" + sabit TP x%.1f R", InpFixedTP_RR) : ""), "\n",
           "Durum: ", g_last_action);
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
   if(InpAOFastPeriod < 1 || InpAOSlowPeriod < 2 || InpAOFastPeriod >= InpAOSlowPeriod)
     {
      Print("Hatali girdiler: 1 <= hizli AO periyodu < yavas AO periyodu olmali (makale: 5/34).");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpAOFastPeriod != 5 || InpAOSlowPeriod != 34)
      Print("BILGI: AO periyotlari makalenin 5/34 ayarindan farkli; tester ile dogrulayin.");
   if(InpAOPivotStrength < 1 || InpAOPivotStrength > 5)
     {
      Print("Hatali girdiler: AO pivot mum sayisi 1-5 olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpPatternLookbackBars < 20 || InpMaxPatternAgeBars < 0 ||
      InpSLSwingBars < 0 || InpSLSwingLookbackBars < 2)
     {
      Print("Hatali girdiler: desen penceresi >= 20, yas/swing ayarlari >= 0 olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMode == AO_SAUCER && InpRequireZeroCross)
      Print("BILGI: Saucer modunda sifir cizgisi sarti kullanilmaz.");
   if(InpFixedTP_RR <= 0.0 || !MathIsValidNumber(InpFixedTP_RR))
     {
      Print("Hatali girdiler: sabit TP carpani pozitif olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLotSize <= 0.0 || !MathIsValidNumber(InpLotSize) ||
      InpRiskPercent <= 0.0 || !MathIsValidNumber(InpRiskPercent))
     {
      Print("Hatali girdiler: lot ve risk % pozitif olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMaxOpenPositions < 0 || InpDeviationPoints < 0 || InpMaxSpreadPoints < 0 ||
      InpMaxPositionMinutes < 0 || InpMaxTradesPerDay < 0 || InpSLBufferPoints < 0)
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

   g_fast_handle = iMA(_Symbol, g_tf, InpAOFastPeriod, 0, MODE_SMA, PRICE_MEDIAN);
   g_slow_handle = iMA(_Symbol, g_tf, InpAOSlowPeriod, 0, MODE_SMA, PRICE_MEDIAN);
   g_atr_handle  = iATR(_Symbol, g_tf, 14);
   if(g_fast_handle == INVALID_HANDLE || g_slow_handle == INVALID_HANDLE ||
      g_atr_handle == INVALID_HANDLE)
     {
      Print("EA baslatilamadi: SMA/ATR gosterge handle olusturulamadi.");
      return INIT_FAILED;
     }

   g_magic_main   = (ulong)InpMagicNumber;
   g_magic_mirror = (InpMagicMirror > 0 ? (ulong)InpMagicMirror : (ulong)InpMagicNumber + 1);
   if(g_magic_mirror == g_magic_main)
      g_magic_mirror = g_magic_main + 1;
   ArrayInitialize(g_planned_entry, 0.0);
   ArrayInitialize(g_planned_sl, 0.0);
   ArrayInitialize(g_planned_tp, 0.0);

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_object_prefix = StringFormat("AO_%d_%s_%s_", InpMagicNumber, _Symbol, EnumToString(g_tf));
   g_last_bar_time = iTime(_Symbol, g_tf, 0);
   RefreshDailyCounters();

   EventSetTimer(1);

   PrintFormat("AO ROBOT hazir: %s TF=%s | mod=%s | AO(%d,%d) median SMA | sifir sarti=%s | magic=%d",
               _Symbol, EnumToString(g_tf), ModeName(), InpAOFastPeriod, InpAOSlowPeriod,
               (InpRequireZeroCross ? "ACIK" : "KAPALI"), InpMagicNumber);
   string risk_txt = (InpUseRiskPercent ? DoubleToString(InpRiskPercent, 1) : "KAPALI");
   string exit_txt = (InpUseIndicatorExit ? "ACIK" : "KAPALI");
   PrintFormat("Risk: lot=%.2f risk=%s | max SL=%.1f ATR | cikis: AO iki ters renkli bar=%s",
               InpLotSize, risk_txt, InpMaxSL_ATR, exit_txt);
   Print("Sinyaller yalnizca KAPANMIS mumlarda degerlendirilir. Acilista gecmise donuk islem acilmaz.");
   PrintFormat(">>> ISLEM MODU: %s | duz magic=%I64u | ters magic=%I64u <<<",
               ModeText(), g_magic_main, g_magic_mirror);
   if(ModeReverseOn())
      Print(">>> TERS ISLEM: BUY sinyalinde SELL, SELL sinyalinde BUY; SL ve TP mesafeleri yer degistirir <<<");
   if(ModeBothOn())
      Print(">>> DUZ+TERS: her sinyalde iki yonde ayri emir acilir; pozisyonlar kendi magic'leriyle ayri yonetilir <<<");
   Print("Akis: AO sifir alti -> iki dip (2. daha yuksek) -> yesil bar -> sifir kirilimi -> AL | SL swing dibi | TP: iki kirmizi bar");

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
