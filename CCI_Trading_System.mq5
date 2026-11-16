//+------------------------------------------------------------------+
//|                                            CCI_Trading_System.mq5 |
//|  CCI Trading System - MT5 ROBOT (EA) - Tam Otomatik             |
//|                                                                  |
//|  Kaynak: Trading Strategy Guides - "CCI Trading System"          |
//|  https://tradingstrategyguides.com/cci-trading-system/            |
//|                                                                  |
//|  Bu bir UZMAN DANIŞMAN (robot) dosyasıdır; gösterge değildir.    |
//|  Grafiğe eklenir, sinyal geldiğinde emir açar ve kapatır.        |
//|  Manuel müdahale gerekmez; tüm kararlar kapanmış mumlarda alınır.|
//|                                                                  |
//|  MAKALEDEKİ İKİ SİSTEM TEK BOTTA BİRLEŞTİRİLDİ:                   |
//|                                                                  |
//|  A) PROFESYONEL SİSTEM (varsayılan, 5 adım):                     |
//|     1) CCI +100'ü yukarı keser (LONG) / -100'ü aşağı keser (SHORT)|
//|     2) Geri çekilme (pullback) beklenir; bu sırada CCI sıfırın   |
//|        üstünde (LONG) / altında (SHORT) kalmalıdır. Sıfırı       |
//|        keserse kurulum iptal olur.                               |
//|     3) 3-5 mumluk geri çekilme tamamlanınca giriş yapılır.       |
//|        Sert düzeltmede kapanış fiyatından girilir.               |
//|     4) SL, en son swing dip/tepe altına/üstüne konur.            |
//|        Giriş sonrası CCI -100'ü (LONG) keserse piyasadan çıkılır.|
//|     5) TP: CCI +200'e (LONG) değerse VEYA CCI sıfırın altına      |
//|        inerse, hangisi önce olursa. SHORT'ta tersi.              |
//|                                                                  |
//|  B) GÜNLÜK (DAY) SİSTEM (5 koşul, M5):                            |
//|     1) Tercih edilen TF: M5                                      |
//|     2) Gürültüyü elemek için +200 / -200 eşikleri                 |
//|     3) İki üst üste aşırı okuma (CCI > +200 veya < -200)         |
//|     4) Fiyat-CCI uyumsuzluğu (divergence)                         |
//|     5) CCI -100'ü yukarı (LONG) / +100'ü aşağı (SHORT) kesince   |
//|        giriş; CCI +200 / -200'ü kesince çıkış.                   |
//|                                                                  |
//|  CCI FORMÜLÜ (makaleden):                                        |
//|     CCI = (Tipik Fiyat - 20 periyotluk TP SMA'sı)                |
//|           / (0.015 x Ortalama Sapma)                             |
//|     Tipik Fiyat = (High + Low + Close) / 3                       |
//|  (MT5'in yerleşik iCCI fonksiyonu bu formülü kullanır.)            |
//|                                                                  |
//|  TASARIM KARARLARI (makalede öznel kalan noktaların              |
//|  otomatikleştirilmesi - ayrıntı README_CCI_Bot.md'de):            |
//|   * "Geri çekilme mumu" = kapanışı açılışından veya bir önceki   |
//|     kapanıştan düşük olan mum (LONG için tersi).                 |
//|   * "En son swing dip/tepe" = kurulum başlangıcından beri        |
//|     görülen en düşük dip / en yüksek tepe (SL tamponu ile).      |
//|   * "Sert düzeltme" = gövdesi ATR'nin InpSharpCorrectionATR      |
//|     katından büyük olan ters yönlü mum.                          |
//|   * Uyumsuzluk = son yarı ile önceki yarının dip/tepe ve CCI     |
//|     değerlerinin karşılaştırılması.                              |
//|   * Giriş, sinyal mumu kapandıktan sonraki ilk tick'te piyasa    |
//|     emriyle yapılır (kapanış fiyatına en yakın otomatik fiyat).  |
//|                                                                  |
//|  GÜVENLİK: Sinyaller YALNIZCA KAPANMIŞ mumlarda değerlendirilir.|
//|  Tek pozisyon (varsayılan), spread filtresi, risk % lot hesabı,  |
//|  günlük limit, işlem saatleri ve para/süre çıkışları dahili.     |
//|  Önce Strategy Tester'da test edin. Yatırım tavsiyesi değildir.|
//+------------------------------------------------------------------+
#property copyright "CCI Trading System - MT5 Robot"
#property version   "1.00"
#property strict
#property description "CCI Trading System (Trading Strategy Guides) tam otomatik MT5 robotu"
#property description "PRO mod: CCI +100/-100 kesimi + geri cekilme + swing SL + CCI 200/sifir TP"
#property description "DAY mod: cift asiri okuma + uyumsuzluk + CCI -100/+100 kesim giris, 200 cikis"
#property description "Sinyaller yalnizca kapanmis mumlarda degerlendirilir"

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Tipler                                                           |
//+------------------------------------------------------------------+
enum ENUM_CCI_MODE
  {
   CCI_MODE_PRO = 0, // Profesyonel sistem (5 adim, varsayilan)
   CCI_MODE_DAY = 1  // Gunluk sistem (5 kosul, uyumsuzluklu)
  };

enum ENUM_SETUP_STATE
  {
   SETUP_IDLE    = 0, // Sinyal bekleniyor
   SETUP_TREND   = 1, // Trend tespit edildi, geri cekilme bekleniyor (PRO)
   SETUP_DAY_EXT = 2, // Asiri okuma goruldu, uyumsuzluk bekleniyor (DAY)
   SETUP_DAY_DIV = 3  // Uyumsuzluk goruldu, CCI kesimi bekleniyor (DAY)
  };

//+------------------------------------------------------------------+
//| Girdiler                                                         |
//+------------------------------------------------------------------+
input group "1) Strateji modu ve CCI ayarlari"
input ENUM_CCI_MODE   InpMode            = CCI_MODE_PRO;    // Strateji modu
input ENUM_TIMEFRAMES InpTimeframe       = PERIOD_CURRENT;  // Islem zaman dilimi (0 = grafik TF)
input int             InpCCIPeriod       = 20;              // CCI periyodu (makale: 20)
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_TYPICAL;   // CCI uygulanan fiyat (makale: Tipik Fiyat)
input double          InpTrendLevel      = 100.0;           // Trend seviyesi (+100 / -100)
input double          InpTakeProfitLevel = 200.0;           // CCI TP seviyesi (+200 / -200)
input double          InpExtremeLevel    = 200.0;           // DAY mod asiri seviye (+200 / -200)
input int             InpPullbackCandles = 3;               // PRO: giris icin gereken geri cekilme mumu (makale: 3-5)
input int             InpMaxSetupBars    = 20;              // Kurulumun gecerlilik suresi (mum, 0 = sinirsiz)
input double          InpSharpCorrectionATR = 1.5;          // Sert duzeltme ATR katı (0 = kapali)
input bool            InpUseHTFFilter    = false;           // Ust TF CCI filtresi (makale sonucu: ust TF daha iyi)
input ENUM_TIMEFRAMES InpHTFTimeframe    = PERIOD_H1;       // Ust TF
input int             InpHTFCCIPeriod    = 20;              // Ust TF CCI periyodu

input group "2) DAY mod uyumsuzluk ayarlari"
input bool InpRequireDivergence      = true;  // DAY modda uyumsuzluk sart olsun mu?
input int  InpDivergenceLookback     = 20;    // Uyumsuzluk icin geriye bakis (mum)
input int  InpConsecutiveExtremeBars = 2;     // Ust uste asiri okuma sayisi (makale: 2)

input group "3) Pozisyon, risk ve emir"
input double InpLotSize          = 0.01;      // Sabit lot
input bool   InpUseRiskPercent   = false;     // true: SL mesafesine gore risk % ile lot hesapla
input double InpRiskPercent      = 1.0;       // Islem basina risk (%)
input ulong  InpMagicNumber      = 20261116;  // Magic Number
input int    InpDeviationPoints  = 20;        // Maksimum sapma (point)
input int    InpMaxSpreadPoints  = 0;         // Maksimum spread (point) - 0 = kapali
input int    InpMaxOpenPositions = 1;         // Ayni anda maks. pozisyon - 0 = sinirsiz
input bool   InpAllowLongs       = true;      // LONG acilsin
input bool   InpAllowShorts      = true;      // SHORT acilsin
input double InpMaxSL_ATR        = 3.0;       // SL mesafesi ATR x bu degeri asarsa islem atlanir (0 = kapali)
input int    InpSLBufferPoints   = 10;        // Swing SL tamponu (point)
input int    InpFixedTpPoints    = 0;         // Sabit TP (point, 0 = kapali; TP varsayilan CCI ile)
input int    InpFixedSlPoints    = 0;         // Sabit SL (point, 0 = kapali; SL varsayilan swing)
input double InpMoneyTakeProfit  = 0.0;       // Para TP (hesap birimi, 0 = kapali)
input double InpMoneyStopLoss    = 0.0;       // Para SL (hesap birimi, 0 = kapali)
input int    InpMaxPositionMinutes = 0;       // Maks. pozisyon suresi (dakika, 0 = kapali)
input double InpMoveToBEAtCCI    = 0.0;       // CCI bu seviyeye ulasinca SL'yi BE'ye cek (0 = kapali)

input group "4) Filtreler (otomatik koruma)"
input bool   InpUseTradingHours  = false;     // Islem saatleri filtresi acik mi?
input int    InpStartHour        = 0;         // Baslangic saati (sunucu saati, 0-23)
input int    InpEndHour          = 24;        // Bitis saati (0-24, 24 = gece yarisi)
input int    InpMaxTradesPerDay  = 0;         // Gunluk maks. islem (0 = sinirsiz)
input double InpMaxDailyLoss     = 0.0;       // Gunluk maks. zarar (hesap birimi, 0 = kapali)

input group "5) Gorsel ve gunluk"
input bool InpDrawArrows   = true;  // Sinyal oklari ciz
input bool InpShowPanel    = true;  // Grafikte bilgi paneli goster
input bool InpDeleteOnExit = true;  // EA kapanirken kendi nesnelerini sil
input bool InpLogSignals   = false; // Her yeni mumda sinyal/seviye logla

//+------------------------------------------------------------------+
//| Global durum                                                     |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES g_tf              = PERIOD_CURRENT;
int             g_cci_handle      = INVALID_HANDLE;
int             g_atr_handle      = INVALID_HANDLE;
int             g_htf_cci_handle  = INVALID_HANDLE;
datetime        g_last_bar_time   = 0;

ENUM_SETUP_STATE g_setup_state    = SETUP_IDLE;
int             g_setup_side      = 0;      // +1 LONG kurulumu, -1 SHORT kurulumu, 0 yok
int             g_setup_bars      = 0;      // Kurulum baslangicindan beri gecen mum
double          g_setup_peak_price = 0.0;   // Kurulumdaki en yuksek/yuksek tepe
double          g_setup_peak_cci   = 0.0;   // Kurulumdaki en yuksek CCI (LONG icin)
double          g_setup_extreme    = 0.0;   // SL icin: en dusuk dip (LONG) / en yuksek tepe (SHORT)
double          g_setup_min_cci    = 0.0;   // Geri cekilme sirasinda gorulen en dusuk CCI (LONG)
double          g_setup_max_cci    = 0.0;   // Geri cekilme sirasinda gorulen en yuksek CCI (SHORT)
int             g_pullback_count   = 0;     // Sayilan geri cekilme mumu
datetime        g_setup_start_time = 0;

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

string ModeName()
  {
   return (InpMode == CCI_MODE_DAY ? "DAY" : "PRO");
  }

string StateName()
  {
   switch(g_setup_state)
     {
      case SETUP_TREND:   return "TREND (geri cekilme bekleniyor)";
      case SETUP_DAY_EXT: return "ASIRI OKUMA (uyumsuzluk bekleniyor)";
      case SETUP_DAY_DIV: return "UYUMSUZLUK (CCI kesimi bekleniyor)";
      default:            return "IDLE (sinyal bekleniyor)";
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

void CloseAllOurPositions(const string reason)
  {
   ulong to_close[];
   ArrayResize(to_close, 0);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int n = ArraySize(to_close);
      if(ArrayResize(to_close, n + 1) == n + 1)
         to_close[n] = ticket;
     }
   for(int i = 0; i < ArraySize(to_close); i++)
      CloseOurPosition(to_close[i], reason);
  }

//+------------------------------------------------------------------+
//| Gosterge okuma                                                   |
//+------------------------------------------------------------------+
bool GetCCI(const int shift, double &value)
  {
   if(g_cci_handle == INVALID_HANDLE)
      return false;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_cci_handle, 0, shift, 1, buf) != 1)
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

bool HTFAllows(const int side)
  {
   if(!InpUseHTFFilter || g_htf_cci_handle == INVALID_HANDLE)
      return true;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_htf_cci_handle, 0, 1, 1, buf) != 1)
      return true; // veri yoksa filtreyi engelleyici yapma
   if(side > 0)
      return (buf[0] > 0.0);
   if(side < 0)
      return (buf[0] < 0.0);
   return false;
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
   datetime today = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(today, dt);
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
//| Kurulum (setup) yonetimi                                         |
//+------------------------------------------------------------------+
void ResetSetup(const string reason)
  {
   if(g_setup_state != SETUP_IDLE && reason != "")
      PrintFormat("Kurulum iptal/sifirlandi: yon=%s sebep=%s",
                  SideName(g_setup_side), reason);
   g_setup_state    = SETUP_IDLE;
   g_setup_side     = 0;
   g_setup_bars     = 0;
   g_setup_peak_price = 0.0;
   g_setup_peak_cci   = 0.0;
   g_setup_extreme    = 0.0;
   g_setup_min_cci    = 0.0;
   g_setup_max_cci    = 0.0;
   g_pullback_count   = 0;
   g_setup_start_time = 0;
  }

void StartSetup(const int side, const ENUM_SETUP_STATE state,
                const double peak_price, const double peak_cci,
                const double extreme, const datetime bar_time)
  {
   g_setup_state      = state;
   g_setup_side       = side;
   g_setup_bars       = 0;
   g_setup_peak_price = peak_price;
   g_setup_peak_cci   = peak_cci;
   g_setup_extreme    = extreme;
   g_setup_min_cci    = peak_cci;
   g_setup_max_cci    = peak_cci;
   g_pullback_count   = 0;
   g_setup_start_time = bar_time;
   g_last_action      = StringFormat("%s kurulumu basladi (%s)",
                                     SideName(side), StateName());
   PrintFormat("KURULUM BASLADI: yon=%s mod=%s durum=%s mum=%s CCI=%.1f",
               SideName(side), ModeName(), StateName(),
               TimeToString(bar_time), peak_cci);
  }

//+------------------------------------------------------------------+
//| Uyumsuzluk (divergence) tespiti - DAY mod                        |
//| Son yari vs onceki yari: fiyat dip/tepe + CCI dip/tepe karsilast.|
//+------------------------------------------------------------------+
bool HasBullishDivergence(const MqlRates &rates[], const double &cci[],
                          const int lookback)
  {
   int half = lookback / 2;
   if(half < 3 || ArraySize(rates) <= lookback + 1 || ArraySize(cci) <= lookback + 1)
      return false;
   int recent_low_idx = 1, prior_low_idx = half + 1;
   for(int i = 1; i <= half; i++)
      if(rates[i].low < rates[recent_low_idx].low)
         recent_low_idx = i;
   for(int i = half + 1; i <= lookback; i++)
      if(rates[i].low < rates[prior_low_idx].low)
         prior_low_idx = i;
   // Fiyat daha dusuk dip, CCI daha yuksek dip yaptiysa pozitif uyumsuzluk
   return (rates[recent_low_idx].low < rates[prior_low_idx].low &&
           cci[recent_low_idx] > cci[prior_low_idx]);
  }

bool HasBearishDivergence(const MqlRates &rates[], const double &cci[],
                          const int lookback)
  {
   int half = lookback / 2;
   if(half < 3 || ArraySize(rates) <= lookback + 1 || ArraySize(cci) <= lookback + 1)
      return false;
   int recent_high_idx = 1, prior_high_idx = half + 1;
   for(int i = 1; i <= half; i++)
      if(rates[i].high > rates[recent_high_idx].high)
         recent_high_idx = i;
   for(int i = half + 1; i <= lookback; i++)
      if(rates[i].high > rates[prior_high_idx].high)
         prior_high_idx = i;
   // Fiyat daha yuksek tepe, CCI daha dusuk tepe yaptiysa negatif uyumsuzluk
   return (rates[recent_high_idx].high > rates[prior_high_idx].high &&
           cci[recent_high_idx] < cci[prior_high_idx]);
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
//| Emir acma                                                        |
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

bool OpenTrade(const int side, const double swing_sl, const string signal_text,
               const datetime signal_time, const double sig_high, const double sig_low)
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

   // SL: varsayilan swing SL; sabit SL aciksa o kullanilir
   double sl = 0.0;
   if(InpFixedSlPoints > 0)
      sl = NormalizePriceToTick(entry - side * InpFixedSlPoints * _Point,
                                (side > 0 ? -1 : 1));
   else if(swing_sl > 0.0)
     {
      double buffer = InpSLBufferPoints * _Point;
      sl = NormalizePriceToTick(swing_sl - side * buffer, (side > 0 ? -1 : 1));
     }

   double tp = 0.0;
   if(InpFixedTpPoints > 0)
      tp = NormalizePriceToTick(entry + side * InpFixedTpPoints * _Point,
                                (side > 0 ? 1 : -1));

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

   // SL mesafesi ATR filtresi (asiri genis SL'li islemleri ele)
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

   string comment = (side > 0 ? "CCI BUY" : "CCI SELL");
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
   ResetSetup("");
   return true;
  }

//+------------------------------------------------------------------+
//| Pozisyon yonetimi - CCI cikislari (makale Adim 4 ve 5)           |
//| Kapanmis mum CCI degerleriyle calisir.                           |
//+------------------------------------------------------------------+
void ManagePositionsByCCI(const double cci1, const double cci2)
  {
   if(CountOurPositions(0) == 0)
      return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
      if(side == 0)
         continue;

      // Adim 5 - TP: CCI 200'e degerse
      if(side > 0 && cci1 >= InpTakeProfitLevel)
        {
         CloseOurPosition(ticket, StringFormat("CCI TP: CCI=%.1f >= %.0f", cci1, InpTakeProfitLevel));
         continue;
        }
      if(side < 0 && cci1 <= -InpTakeProfitLevel)
        {
         CloseOurPosition(ticket, StringFormat("CCI TP: CCI=%.1f <= -%.0f", cci1, InpTakeProfitLevel));
         continue;
        }

      // Adim 5 - TP yedegi: CCI sifiri keserse
      if(side > 0 && cci2 >= 0.0 && cci1 < 0.0)
        {
         CloseOurPosition(ticket, StringFormat("CCI sifir kesimi (LONG cikis): CCI=%.1f", cci1));
         continue;
        }
      if(side < 0 && cci2 <= 0.0 && cci1 > 0.0)
        {
         CloseOurPosition(ticket, StringFormat("CCI sifir kesimi (SHORT cikis): CCI=%.1f", cci1));
         continue;
        }

      // Adim 4 - Iptal: giris sonrasi CCI ters -100/+100'u keserse
      if(side > 0 && cci2 >= -InpTrendLevel && cci1 < -InpTrendLevel)
        {
         CloseOurPosition(ticket, StringFormat("CCI iptal: CCI -100 altina indi (%.1f)", cci1));
         continue;
        }
      if(side < 0 && cci2 <= InpTrendLevel && cci1 > InpTrendLevel)
        {
         CloseOurPosition(ticket, StringFormat("CCI iptal: CCI +100 ustune cikti (%.1f)", cci1));
         continue;
        }

      // Opsiyonel: CCI seviyesinde SL'yi BE'ye cek
      if(InpMoveToBEAtCCI > 0.0)
        {
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur_sl     = PositionGetDouble(POSITION_SL);
         bool   hit        = (side > 0 && cci1 >= InpMoveToBEAtCCI) ||
                             (side < 0 && cci1 <= -InpMoveToBEAtCCI);
         bool   need_move  = (side > 0 && (cur_sl <= 0.0 || cur_sl < open_price)) ||
                             (side < 0 && (cur_sl <= 0.0 || cur_sl > open_price));
         if(hit && need_move)
           {
            double be_sl = NormalizePriceToTick(open_price, (side > 0 ? 1 : -1));
            double cur_tp = PositionGetDouble(POSITION_TP);
            if(trade.PositionModify(ticket, be_sl, cur_tp))
               PrintFormat("SL BE'ye cekildi: ticket=%I64u CCI=%.1f", ticket, cci1);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Tick duzeyinde cikislar (para / sure)                            |
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
     }
  }

//+------------------------------------------------------------------+
//| PRO mod isleme (makale: Profesyonel 5 adim)                      |
//+------------------------------------------------------------------+
void ProcessPROMode(const MqlRates &rates[], const double &cci[],
                    const double &atr[])
  {
   if(ArraySize(rates) < 3 || ArraySize(cci) < 3)
      return;
   double cci1 = cci[1]; // son kapanmis mum
   double cci2 = cci[2]; // bir onceki kapanmis mum
   double atr1 = (ArraySize(atr) > 1 ? atr[1] : 0.0);

   // --- IDLE: Adim 1 - CCI trend seviyesini kesiyor mu? ---
   if(g_setup_state == SETUP_IDLE)
     {
      // LONG: CCI +100'u yukari keser
      if(InpAllowLongs && cci2 <= InpTrendLevel && cci1 > InpTrendLevel && HTFAllows(1))
        {
         StartSetup(1, SETUP_TREND, rates[1].high, cci1, rates[1].low, rates[1].time);
         PrintFormat("Adim 1 (LONG): CCI +%.0f kesildi (%.1f -> %.1f). Geri cekilme bekleniyor.",
                     InpTrendLevel, cci2, cci1);
         return;
        }
      // SHORT: CCI -100'u asagi keser
      if(InpAllowShorts && cci2 >= -InpTrendLevel && cci1 < -InpTrendLevel && HTFAllows(-1))
        {
         StartSetup(-1, SETUP_TREND, rates[1].low, cci1, rates[1].high, rates[1].time);
         PrintFormat("Adim 1 (SHORT): CCI -%.0f kesildi (%.1f -> %.1f). Geri cekilme bekleniyor.",
                     InpTrendLevel, cci2, cci1);
         return;
        }
      return;
     }

   // --- TREND: Adim 2-3 - geri cekilme ve giris ---
   if(g_setup_state != SETUP_TREND || g_setup_side == 0)
      return;

   g_setup_bars++;

   // Sure asimi
   if(InpMaxSetupBars > 0 && g_setup_bars > InpMaxSetupBars)
     {
      ResetSetup("kurulum suresi doldu");
      return;
     }

   int side = g_setup_side;

   // Adim 2 - Iptal: CCI sifiri keserse kurulum gecersiz
   if(side > 0 && cci1 < 0.0)
     {
      PrintFormat("Adim 2 iptal (LONG): CCI sifirin altina indi (%.1f). Kurulum iptal.", cci1);
      ResetSetup("CCI sifir altina indi");
      return;
     }
   if(side < 0 && cci1 > 0.0)
     {
      PrintFormat("Adim 2 iptal (SHORT): CCI sifirin ustune cikti (%.1f). Kurulum iptal.", cci1);
      ResetSetup("CCI sifir ustune cikti");
      return;
     }

   // Zirve ve asiri degerleri guncelle
   if(side > 0)
     {
      g_setup_peak_price = MathMax(g_setup_peak_price, rates[1].high);
      g_setup_peak_cci   = MathMax(g_setup_peak_cci, cci1);
      g_setup_extreme    = MathMin(g_setup_extreme, rates[1].low);
      g_setup_min_cci    = MathMin(g_setup_min_cci, cci1);
     }
   else
     {
      g_setup_peak_price = MathMin(g_setup_peak_price, rates[1].low);
      g_setup_peak_cci   = MathMin(g_setup_peak_cci, cci1);
      g_setup_extreme    = MathMax(g_setup_extreme, rates[1].high);
      g_setup_max_cci    = MathMax(g_setup_max_cci, cci1);
     }

   // Geri cekilme mumu sayimi: LONG icin kapanisi dusen, SHORT icin kapanisi yukselten mum
   bool is_pullback = false;
   if(side > 0)
      is_pullback = (rates[1].close < rates[1].open || rates[1].close < rates[2].close);
   else
      is_pullback = (rates[1].close > rates[1].open || rates[1].close > rates[2].close);
   if(is_pullback)
      g_pullback_count++;

   // Sert duzeltme: govdesi ATR'nin katindan buyuk ters mum
   bool sharp = false;
   if(InpSharpCorrectionATR > 0.0 && atr1 > 0.0)
     {
      double body = MathAbs(rates[1].close - rates[1].open);
      if(side > 0 && rates[1].close < rates[1].open && body > InpSharpCorrectionATR * atr1)
         sharp = true;
      if(side < 0 && rates[1].close > rates[1].open && body > InpSharpCorrectionATR * atr1)
         sharp = true;
     }

   // Adim 3 - Giris sarti: yeterli geri cekilme + CCI zirveden geri cekilmis
   bool cci_pulled_back = (side > 0 && cci1 < g_setup_peak_cci) ||
                          (side < 0 && cci1 > g_setup_peak_cci);
   bool enough_pullback = (g_pullback_count >= InpPullbackCandles);
   bool cci_still_strong = (side > 0 && cci1 > 0.0) || (side < 0 && cci1 < 0.0);

   if(InpLogSignals)
      PrintFormat("PRO[%s] yon=%s CCI=%.1f zirveCCI=%.1f geriCekilme=%d/%d sert=%s",
                  TimeToString(rates[1].time, TIME_DATE | TIME_MINUTES),
                  SideName(side), cci1, g_setup_peak_cci,
                  g_pullback_count, InpPullbackCandles,
                  (sharp ? "EVET" : "hayir"));

   if((sharp || (enough_pullback && cci_pulled_back)) && cci_still_strong)
     {
      string text = (sharp
                     ? StringFormat("Adim 3 sert duzeltme -> %s", SideName(side))
                     : StringFormat("Adim 3 geri cekilme %d mum -> %s",
                                    g_pullback_count, SideName(side)));
      // Adim 4: SL = en son swing dip/tepe (kurulumdaki asiri deger)
      OpenTrade(side, g_setup_extreme, text, rates[1].time,
                rates[1].high, rates[1].low);
     }
  }

//+------------------------------------------------------------------+
//| DAY mod isleme (makale: Gunluk 5 kosul)                          |
//+------------------------------------------------------------------+
void ProcessDAYMode(const MqlRates &rates[], const double &cci[],
                    const double &atr[])
  {
   if(ArraySize(rates) < 3 || ArraySize(cci) < 3)
      return;
   double cci1 = cci[1];
   double cci2 = cci[2];

   // --- IDLE: Kosul 2-3 - iki ust uste asiri okuma ---
   if(g_setup_state == SETUP_IDLE)
     {
      int need = MathMax(1, InpConsecutiveExtremeBars);
      bool long_extreme = true, short_extreme = true;
      for(int i = 1; i <= need; i++)
        {
         if(ArraySize(cci) <= i)
           {
            long_extreme = false; short_extreme = false; break;
           }
         if(cci[i] >= -InpExtremeLevel)
            long_extreme = false;
         if(cci[i] <= InpExtremeLevel)
            short_extreme = false;
        }
      if(InpAllowLongs && long_extreme && HTFAllows(1))
        {
         double lowest = rates[1].low;
         for(int i = 1; i < ArraySize(rates) && i <= InpDivergenceLookback; i++)
            lowest = MathMin(lowest, rates[i].low);
         StartSetup(1, SETUP_DAY_EXT, rates[1].high, cci1, lowest, rates[1].time);
         PrintFormat("DAY Kosul 3 (LONG): %d ust uste CCI < -%.0f. Uyumsuzluk bekleniyor.",
                     need, InpExtremeLevel);
         return;
        }
      if(InpAllowShorts && short_extreme && HTFAllows(-1))
        {
         double highest = rates[1].high;
         for(int i = 1; i < ArraySize(rates) && i <= InpDivergenceLookback; i++)
            highest = MathMax(highest, rates[i].high);
         StartSetup(-1, SETUP_DAY_EXT, rates[1].low, cci1, highest, rates[1].time);
         PrintFormat("DAY Kosul 3 (SHORT): %d ust uste CCI > +%.0f. Uyumsuzluk bekleniyor.",
                     need, InpExtremeLevel);
         return;
        }
      return;
     }

   if(g_setup_side == 0)
      return;

   g_setup_bars++;
   if(InpMaxSetupBars > 0 && g_setup_bars > InpMaxSetupBars)
     {
      ResetSetup("kurulum suresi doldu");
      return;
     }

   int side = g_setup_side;

   // Asiri degerleri guncelle (SL icin)
   if(side > 0)
      g_setup_extreme = MathMin(g_setup_extreme, rates[1].low);
   else
      g_setup_extreme = MathMax(g_setup_extreme, rates[1].high);

   // --- Kosul 4: Uyumsuzluk ---
   if(g_setup_state == SETUP_DAY_EXT)
     {
      bool div_ok = true;
      if(InpRequireDivergence)
        {
         if(side > 0)
            div_ok = HasBullishDivergence(rates, cci, InpDivergenceLookback);
         else
            div_ok = HasBearishDivergence(rates, cci, InpDivergenceLookback);
        }
      if(div_ok)
        {
         g_setup_state = SETUP_DAY_DIV;
         g_setup_bars  = 0;
         PrintFormat("DAY Kosul 4 (%s): uyumsuzluk goruldu. CCI kesimi bekleniyor.",
                     SideName(side));
        }
      else if(InpLogSignals)
         PrintFormat("DAY[%s] yon=%s uyumsuzluk yok (CCI=%.1f)",
                     TimeToString(rates[1].time, TIME_DATE | TIME_MINUTES),
                     SideName(side), cci1);
      return;
     }

   // --- Kosul 5: CCI kesimiyle giris ---
   if(g_setup_state == SETUP_DAY_DIV)
     {
      bool trigger = false;
      if(side > 0 && cci2 <= -InpTrendLevel && cci1 > -InpTrendLevel)
         trigger = true;
      if(side < 0 && cci2 >= InpTrendLevel && cci1 < InpTrendLevel)
         trigger = true;
      if(trigger)
        {
         string text = StringFormat("DAY Kosul 5 CCI kesimi -> %s", SideName(side));
         OpenTrade(side, g_setup_extreme, text, rates[1].time,
                   rates[1].high, rates[1].low);
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
   double cci1 = 0.0, cci2 = 0.0;
   bool has_cci = GetCCI(1, cci1) && GetCCI(2, cci2);
   double atr1 = 0.0;
   GetATR(1, atr1);

   string cci_text = (has_cci
                      ? StringFormat("CCI=%.1f (onceki %.1f) | ATR=%.5f", cci1, cci2, atr1)
                      : "CCI hesaplaniyor...");

   string setup_text;
   if(g_setup_state == SETUP_IDLE)
      setup_text = "IDLE";
   else
      setup_text = StringFormat("%s | yon=%s | mum=%d | geriCekilme=%d/%d | asiri=%s",
                                StateName(), SideName(g_setup_side), g_setup_bars,
                                g_pullback_count, InpPullbackCandles,
                                DoubleToString(g_setup_extreme, _Digits));

   Comment("CCI Trading System ROBOT v1.00\n",
           "Mod: ", ModeName(),
           " | Sembol: ", _Symbol, " | TF: ", EnumToString(g_tf),
           " | spread: ", DoubleToString((SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                                          SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point, 0),
           " point\n",
           cci_text, "\n",
           "Kurulum: ", setup_text, "\n",
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
   int needed = MathMax(100, MathMax(InpCCIPeriod * 5,
                                     MathMax(InpDivergenceLookback * 2 + 10,
                                             InpMaxSetupBars + 50)));
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, g_tf, 0, needed, rates);
   if(copied < 10)
     {
      g_last_action = StringFormat("Yetersiz mum verisi: %d", copied);
      return;
     }

   double cci[];
   ArraySetAsSeries(cci, true);
   if(g_cci_handle != INVALID_HANDLE)
      CopyBuffer(g_cci_handle, 0, 0, needed, cci);
   double atr[];
   ArraySetAsSeries(atr, true);
   if(g_atr_handle != INVALID_HANDLE)
      CopyBuffer(g_atr_handle, 0, 0, needed, atr);

   if(ArraySize(cci) < 3 || ArraySize(atr) < 3)
     {
      g_last_action = "Gosterge verisi henuz hazir degil";
      return;
     }

   double cci1 = cci[1], cci2 = cci[2];

   if(InpLogSignals)
      PrintFormat("CCI[%s] CCI=%.1f (onceki %.1f) | durum=%s",
                  TimeToString(rates[1].time, TIME_DATE | TIME_MINUTES),
                  cci1, cci2, StateName());

   // 1) Once acik pozisyonlarin CCI cikislari (Adim 4-5)
   ManagePositionsByCCI(cci1, cci2);

   // 2) Pozisyon aciksa yeni kurulum baslatma (tek pozisyon disiplini)
   if(CountOurPositions(0) > 0)
     {
      if(g_setup_state != SETUP_IDLE)
         ResetSetup("pozisyon acik");
      g_last_action = "Pozisyon acik, yeni sinyal bekleniyor";
      return;
     }

   // 3) Moda gore giris isleme
   if(InpMode == CCI_MODE_DAY)
      ProcessDAYMode(rates, cci, atr);
   else
      ProcessPROMode(rates, cci, atr);
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
   if(InpCCIPeriod < 2 || InpHTFCCIPeriod < 2)
     {
      Print("Hatali girdiler: CCI periyodu en az 2 olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpTrendLevel <= 0.0 || InpTakeProfitLevel <= InpTrendLevel ||
      InpExtremeLevel < InpTrendLevel)
     {
      Print("Hatali girdiler: 0 < TrendLevel < TakeProfitLevel <= ExtremeLevel olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpPullbackCandles < 1 || InpPullbackCandles > 10)
     {
      Print("Hatali girdiler: geri cekilme mumu 1-10 arasinda olmali (makale: 3-5).");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpDivergenceLookback < 6 || InpConsecutiveExtremeBars < 1 ||
      InpConsecutiveExtremeBars > 5)
     {
      Print("Hatali girdiler: uyumsuzluk bakisi en az 6, asiri okuma 1-5 arasinda olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLotSize <= 0.0 || !MathIsValidNumber(InpLotSize) ||
      InpRiskPercent <= 0.0 || !MathIsValidNumber(InpRiskPercent))
     {
      Print("Hatali girdiler: lot ve risk % pozitif olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMaxSetupBars < 0 || InpMaxOpenPositions < 0 || InpDeviationPoints < 0 ||
      InpMaxSpreadPoints < 0 || InpSLBufferPoints < 0 || InpFixedTpPoints < 0 ||
      InpFixedSlPoints < 0 || InpMaxPositionMinutes < 0 || InpMaxTradesPerDay < 0)
     {
      Print("Hatali girdiler: sayisal ayarlar negatif olamaz.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMoneyTakeProfit < 0.0 || InpMoneyStopLoss < 0.0 ||
      InpMaxDailyLoss < 0.0 || InpSharpCorrectionATR < 0.0 ||
      InpMaxSL_ATR < 0.0 || InpMoveToBEAtCCI < 0.0)
     {
      Print("Hatali girdiler: para/ATR/CCI esikleri negatif olamaz (0 = kapali).");
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
   if(InpTakeProfitLevel < InpExtremeLevel)
      Print("BILGI: TP seviyesi asiri seviyeden dusuk; DAY modda cikis giristen once tetiklenebilir.");
   if(InpMode == CCI_MODE_DAY && InpTimeframe != PERIOD_M5 && InpTimeframe != PERIOD_CURRENT)
      Print("BILGI: Makale DAY sistem icin M5 onerir; su anki TF: ", EnumToString(g_tf));

   if(!SymbolSelect(_Symbol, true))
     {
      Print("EA baslatilamadi: sembol secilemiyor.");
      return INIT_FAILED;
     }

   g_cci_handle = iCCI(_Symbol, g_tf, InpCCIPeriod, InpAppliedPrice);
   g_atr_handle = iATR(_Symbol, g_tf, 14);
   if(g_cci_handle == INVALID_HANDLE || g_atr_handle == INVALID_HANDLE)
     {
      Print("EA baslatilamadi: CCI/ATR gosterge handle olusturulamadi.");
      return INIT_FAILED;
     }
   if(InpUseHTFFilter)
     {
      g_htf_cci_handle = iCCI(_Symbol, InpHTFTimeframe, InpHTFCCIPeriod, InpAppliedPrice);
      if(g_htf_cci_handle == INVALID_HANDLE)
        {
         Print("EA baslatilamadi: ust TF CCI handle olusturulamadi.");
         return INIT_FAILED;
        }
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_object_prefix = StringFormat("CCI_%I64u_%s_%s_",
                                  InpMagicNumber, _Symbol, EnumToString(g_tf));
   g_last_bar_time = iTime(_Symbol, g_tf, 0);
   RefreshDailyCounters();
   ResetSetup("");

   EventSetTimer(1);

   PrintFormat("CCI ROBOT hazir: %s TF=%s mod=%s | CCI periyot=%d trend=%.0f TP=%.0f | lot=%.2f risk%%=%s magic=%I64u",
               _Symbol, EnumToString(g_tf), ModeName(), InpCCIPeriod,
               InpTrendLevel, InpTakeProfitLevel, InpLotSize,
               (InpUseRiskPercent ? DoubleToString(InpRiskPercent, 2) : "kapali"),
               InpMagicNumber);
   Print("Sinyaller yalnizca KAPANMIS mumlarda degerlendirilir. Acilista gecmise donuk islem acilmaz.");
   Print("PRO: CCI +100/-100 kesimi -> geri cekilme (CCI sifir ustunde/altinda) -> 3-5 mum -> giris | SL swing, TP CCI 200/sifir");
   Print("DAY: cift asiri okuma (+/-200) -> uyumsuzluk -> CCI -100/+100 kesimi -> giris | cikis CCI +/-200 kesimi");

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
