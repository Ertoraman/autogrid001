//+------------------------------------------------------------------+
//|                                       AndrewsPitchfork_Bot.mq5   |
//|  ANDREWS PITCHFORK - MT5 ROBOT (EA) - Tam Otomatik               |
//|                                                                  |
//|  Kaynak: Trading Strategy Guides - "Andrews Pitchfork Trading    |
//|  Strategy"                                                       |
//|  https://tradingstrategyguides.com/andrews-pitchfork-trading-strategy/|
//|                                                                  |
//|  Bu bir UZMAN DANISMAN (robot) dosyasidir; gosterge degildir.    |
//|  Grafige eklenir, sinyal geldiginde emir acar/kapatir.           |
//|  Manuel mudahale gerekmez; tum kararlar KAPANMIS mumlarda alinir.|
//|                                                                  |
//|  PITCHFORK GEOMETRISI:                                           |
//|   3 pivot: P1 (baslangic), P2, P3.                              |
//|   Median cizgi = P1'den gecen ve P2-P3 orta noktasina uzanan     |
//|   cizgi. Ust/alt kanal cizgileri P2 ve P3'ten gecen paraleller.  |
//|   Fiyat medyan cizgisine yonelir (regresyon cizgisi gibi).       |
//|                                                                  |
//|  MAKALENIN ALIM KURALLARI (5 adim; SATIM tam tersi):             |
//|   1) Ucan uc pivotu bul (yukselen dipler/tepeler).               |
//|   2) Pitchfork'u P1 -> P2 -> P3 uzerinden ciz.                   |
//|   3) ALT kanal destek cizgisinin ILK yeniden testinde              |
//|      piyasa fiyatindan AL.                                       |
//|   4) TP1 = kismi kar median cizgisinde; TP2 = UST kanal          |
//|      direnc cizgisi. TP1 sonrasi SL'yi BE'ye cek.                |
//|   5) SL = ALT kanal cizgisinin altinda + 20-30 pip tampon.       |
//|                                                                  |
//|  Makalenin 3 temel ilkesi (bot aynen uygular):                   |
//|   * Fiyat medyan cizgisine yonelir.                              |
//|   * Medyan kirilirsa, medyana geri donus (retest) olasiligi      |
//|     yuksektir  -> PF_MEDIAN_RETEST giris modu.                   |
//|   * Kanal ters yonde kirilirsa duygu degisir, trend donebilir     |
//|     -> InpExitOnChannelBreak ve kanal gecersizligi.              |
//|                                                                  |
//|  TASARIM KARARLARI (makalede oznel kalan noktalar - ayrintili    |
//|  aciklama README_Pitchfork_Bot.md icinde):                       |
//|   * "Pivot" = InpPivotStrength kadar bar saga/sola ekstrem       |
//|     olan swing tepe/dip. Uc pivotun sirasi ve geometrisi         |
//|     (yukselen dip / dusen tepe) otomatik dogrulanir.             |
//|   * "Ilk retest" = P3'ten sonraki barlarda alt/ust kanal          |
//|     cizgisine ilk temas; daha once temas veya kapanisla          |
//|     kirilma olduysa kurulum gecersiz.                            |
//|   * "Temas" = bar fitili cizgiye InpLineToleranceATR x ATR        |
//|     kadar yaklasir ve kapanis cizginin dogru tarafinda kalir.     |
//|   * "20-30 pip tampon" = InpSLBufferPips (vars. 25).              |
//|   * TP1 = median, TP2 = karsi kanal cizgisi; ikisi de giris       |
//|     anindaki cizgi degerlerine gore sabitlenir (broker TP).       |
//|   * Kismi kapanis = InpPartialClosePercent (vars. %50).          |
//|                                                                  |
//|  GUVENLIK: Sinyaller YALNIZCA KAPANMIS mumlarda degerlendirilir. |
//|  Tek pozisyon (varsayilan), spread filtresi, risk % lot hesabi,  |
//|  gunluk limit, islem saatleri, para/sure/BE cikislari dahildir.   |
//|  Once Strategy Tester'da test edin. Yatirim tavsiyesi degildir.   |
//+------------------------------------------------------------------+
#property copyright "Andrews Pitchfork - MT5 Robot"
#property version   "1.00"
#property strict
#property description "Andrews Pitchfork (3 pivot) tam otomatik MT5 robotu"
#property description "Giris: alt/ust kanal cizgisinin ilk retesti veya median retesti"
#property description "TP1: median (kismi) | TP2: karsi kanal cizgisi | SL: kanal disi + 20-30 pip"
#property description "Sinyaller yalnizca kapanmis mumlarda degerlendirilir"

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Tipler                                                           |
//+------------------------------------------------------------------+
enum ENUM_PF_ENTRY
  {
   PF_LINE_RETEST   = 0, // Kanal cizgisinin ilk retesti (makale Adim 3)
   PF_MEDIAN_RETEST = 1  // Median kirilimi sonrasi median retesti
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

input group "1) Pitchfork (3 pivot)"
input ENUM_TIMEFRAMES InpTimeframe      = PERIOD_CURRENT; // Islem zaman dilimi (0 = grafik TF)
input int             InpPivotStrength  = 3;    // Pivot icin bar sayisi (her iki yan)
input int             InpLookbackBars   = 400;  // Pivot tarama penceresi (mum)
input int             InpMaxForkAgeBars = 200;  // P3 en fazla kac bar once olusmali
input int             InpMinForkSpanBars = 20;  // P1-P3 arasi min. bar sayisi
input int             InpMaxWaitRetestBars = 80; // Kurulum gecerlilik suresi (mum)

input group "2) Giris"
input ENUM_PF_ENTRY   InpEntryMode      = PF_LINE_RETEST; // Giris modu
input double          InpLineToleranceATR = 0.15; // Cizgiye temas toleransi (ATR kati)

input group "3) Cikis (makale Adim 4-5)"
input double          InpPartialClosePercent = 50.0; // TP1'de kismi kapanis (%)
input bool            InpMoveToBEAfterTP1 = true; // TP1 sonrasi SL'yi BE'ye cek
input int             InpSLBufferPips   = 25;   // SL tamponu (pip, makale: 20-30)
input bool            InpExitOnChannelBreak = false; // Kanal ters yonde kirilirsa kapat
input bool            InpUseFixedTP     = true; // Broker TP = TP2 (kanal cizgisi)

input group "4) Pozisyon ve risk"
input double          InpLotSize        = 0.01; // Sabit lot
input bool            InpUseRiskPercent = false; // Risk % ile lot hesabi
input double          InpRiskPercent    = 1.0;  // Islem basina risk (%)
input int             InpMagicNumber    = 20261120; // Magic number
input int             InpDeviationPoints = 20;  // Maksimum sapma (point)
input int             InpMaxSpreadPoints = 0;   // Maksimum spread (point) - 0 = kapali
input int             InpMaxOpenPositions = 1;  // Maksimum acik pozisyon (0 = sinirsiz)
input bool            InpAllowLongs     = true; // LONG islemler acik
input bool            InpAllowShorts    = true; // SHORT islemler acik
input ENUM_TRADE_MODE InpTradeMode      = TRADE_MODE_NORMAL; // Islem modu: 0=duz 1=ters 2=duz+ters (ayri magic)
input int             InpMagicMirror     = 0;    // Ters islem magic (0 = InpMagicNumber+1)
input double          InpMaxSL_ATR      = 5.0;  // SL mesafesi ATR x bu degeri asarsa islem atlanir (0 = kapali)
input double          InpMoneyTakeProfit = 0.0; // Para TP (hesap birimi, 0 = kapali)
input double          InpMoneyStopLoss  = 0.0;  // Para SL (hesap birimi, 0 = kapali)
input int             InpMaxPositionMinutes = 0; // Maks. pozisyon suresi (dakika, 0 = kapali)
input double          InpMoveToBEAtRR   = 0.0;  // Kar R x bu kadar olunca SL'yi BE'ye cek (0 = kapali)

input group "5) Filtreler (otomatik koruma)"
input bool            InpUseTradingHours = false; // Islem saatleri filtresi
input int             InpStartHour      = 0;    // Baslangic saati (sunucu saati, 0-23)
input int             InpEndHour        = 24;   // Bitis saati (0-24, 24 = gece yarisi)
input int             InpMaxTradesPerDay = 0;   // Gunluk maks. islem (0 = sinirsiz)
input double          InpMaxDailyLoss   = 0.0;  // Gunluk maks. zarar (hesap birimi, 0 = kapali)

input group "6) Gorsel ve log"
input bool            InpDrawFork       = true; // Pitchfork cizgilerini grafikte ciz
input int             InpDrawForwardBars = 20;  // Cizgileri kac bar ileri uzat
input bool            InpDrawArrows     = true; // Sinyal oklarini ciz
input bool            InpShowPanel      = true; // Bilgi panelini goster
input bool            InpDeleteOnExit   = true; // EA kaldirilinca grafik nesnelerini sil
input bool            InpLogSignals     = false; // Her mumda detayli log

//+------------------------------------------------------------------+
//| Globaller                                                        |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES g_tf = PERIOD_CURRENT;

int      g_atr_handle    = INVALID_HANDLE;
datetime g_last_bar_time = 0;

bool     g_fork_valid    = false;
int      g_fork_dir      = 0;      // +1 yukselen (alim), -1 dusen (satim)
double   g_fork_slope    = 0.0;    // bar basina fiyat degisimi
int      g_t1 = 0, g_t2 = 0, g_t3 = 0;
double   g_p1 = 0.0, g_p2 = 0.0, g_p3 = 0.0;

double   g_tp1_level[2]  = {0.0, 0.0};   // [0]=duz, [1]=ters
double   g_tp2_level[2]  = {0.0, 0.0};
bool     g_tp1_done[2]   = {false, false};

int      g_signal_count  = 0;
int      g_skip_count    = 0;
int      g_trades_today  = 0;
datetime g_trades_day    = 0;
double   g_day_start_equity = 0.0;
string   g_last_action   = "Baslatiliyor";
string   g_object_prefix = "";

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
   if(InpEntryMode == PF_MEDIAN_RETEST)
      return "MEDIAN RETEST";
   return "KANAL CIZGISI ILK RETEST";
  }

string ForkName()
  {
   if(!g_fork_valid)
      return "yok";
   return (g_fork_dir > 0 ? "YUKSELEN (alim)" : "DUSEN (satim)");
  }

string StateName()
  {
   if(CountOurPositions(0) > 0)
      return "POZISYON ACIK";
   if(!g_fork_valid)
      return "IDLE (pitchfork bekleniyor)";
   return "PITCHFORK HAZIR (retest bekleniyor)";
  }

double TickSize()
  {
   double size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(size <= 0.0)
      size = _Point;
   return size;
  }

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
//| Gosterge                                                        |
//+------------------------------------------------------------------+
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
//| Pivot tespiti                                                    |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Pitchfork geometrisi                                             |
//+------------------------------------------------------------------+
void InvalidateFork()
  {
   g_fork_valid = false;
   g_fork_dir   = 0;
   g_fork_slope = 0.0;
   g_t1 = g_t2 = g_t3 = 0;
   g_p1 = g_p2 = g_p3 = 0.0;
  }

// Pivot fiyatindan, verilen bar indeksine cizgi degeri
double ForkLineAt(const double pivot_price, const int pivot_idx, const int bar_idx)
  {
   return pivot_price + g_fork_slope * (double)(pivot_idx - bar_idx);
  }

double ForkMedianAt(const int bar_idx)
  {
   if(!g_fork_valid)
      return 0.0;
   return ForkLineAt(g_p1, g_t1, bar_idx);
  }

double ForkUpperAt(const int bar_idx)
  {
   if(!g_fork_valid)
      return 0.0;
   if(g_fork_dir > 0)
      return ForkLineAt(g_p2, g_t2, bar_idx);   // yukselen: P2 = tepe
   return ForkLineAt(g_p3, g_t3, bar_idx);      // dusen:   P3 = tepe
  }

double ForkLowerAt(const int bar_idx)
  {
   if(!g_fork_valid)
      return 0.0;
   if(g_fork_dir > 0)
      return ForkLineAt(g_p3, g_t3, bar_idx);   // yukselen: P3 = dip
   return ForkLineAt(g_p2, g_t2, bar_idx);      // dusen:   P2 = dip
  }

// Uc gecerli pivotu bul: P1 (en eski) -> P2 -> P3 (en yeni)
bool FindFork(const MqlRates &rates[])
  {
   InvalidateFork();
   int n = ArraySize(rates);
   int strength = InpPivotStrength;
   int limit = MathMin(InpLookbackBars, n - strength - 2);
   if(limit <= strength + 3)
      return false;

   int    idxs[];
   double prices[];
   int    types[];   // +1 tepe, -1 dip
   ArrayResize(idxs, 0);
   ArrayResize(prices, 0);
   ArrayResize(types, 0);
   int cnt = 0;

   // yeni -> eski (indeks artan)
   for(int i = strength + 1; i <= limit; i++)
     {
      int type = 0;
      double price = 0.0;
      if(IsPivot(rates, i, strength, true))
        {
         type  = 1;
         price = rates[i].high;
        }
      else if(IsPivot(rates, i, strength, false))
        {
         type  = -1;
         price = rates[i].low;
        }
      else
         continue;
      ArrayResize(idxs, cnt + 1);
      ArrayResize(prices, cnt + 1);
      ArrayResize(types, cnt + 1);
      idxs[cnt]   = i;
      prices[cnt] = price;
      types[cnt]  = type;
      cnt++;
     }
   if(cnt < 3)
      return false;

   for(int a = 0; a < cnt - 2; a++)          // P3 (en yeni)
     {
      if((idxs[a] - 1) > InpMaxForkAgeBars)
         break;                              // daha eskiler de gecersiz
      for(int b = a + 1; b < cnt - 1; b++)   // P2
        {
         if(types[b] == types[a])
            continue;
         for(int c = b + 1; c < cnt; c++)    // P1 (en eski)
           {
            if(types[c] != types[a])
               continue;
            if((idxs[c] - idxs[a]) < InpMinForkSpanBars)
               continue;

            double p1 = prices[c];
            double p2 = prices[b];
            double p3 = prices[a];
            int dir = 0;
            if(types[a] < 0)                 // P3 dip, P2 tepe, P1 dip -> yukselen
              {
               if(!(p2 > p3 && p3 > p1))
                  continue;
               dir = 1;
              }
            else                             // P3 tepe, P2 dip, P1 tepe -> dusen
              {
               if(!(p2 < p3 && p3 < p1))
                  continue;
               dir = -1;
              }

            double t1 = (double)idxs[c];
            double t2 = (double)idxs[b];
            double t3 = (double)idxs[a];
            double tM = (t2 + t3) / 2.0;
            double pM = (p2 + p3) / 2.0;
            if(MathAbs(t1 - tM) < 1.0)
               continue;
            double slope = (pM - p1) / (t1 - tM);
            if(dir > 0 && slope <= 0.0)
               continue;
            if(dir < 0 && slope >= 0.0)
               continue;

            g_fork_valid = true;
            g_fork_dir   = dir;
            g_fork_slope = slope;
            g_t1 = idxs[c];
            g_t2 = idxs[b];
            g_t3 = idxs[a];
            g_p1 = p1;
            g_p2 = p2;
            g_p3 = p3;
            return true;
           }
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Cizim                                                            |
//+------------------------------------------------------------------+
void DrawForkLine(const string tag, const int pivot_idx, const double pivot_price, const color c,
                  const int forward_bars, const ENUM_LINE_STYLE style)
  {
   string name = g_object_prefix + "PF_" + tag;
   ObjectDelete(0, name);
   if(!g_fork_valid || pivot_idx <= 0)
      return;
   int secs = PeriodSeconds(g_tf);
   datetime t_start = iTime(_Symbol, g_tf, pivot_idx);
   if(t_start <= 0)
      return;
   datetime t_end   = iTime(_Symbol, g_tf, 0) + secs * forward_bars;
   double   p_end   = ForkLineAt(pivot_price, pivot_idx, -forward_bars);
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t_start, pivot_price, t_end, p_end))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void DrawFork()
  {
   if(!InpDrawFork)
      return;
   if(!g_fork_valid)
     {
      ObjectDelete(0, g_object_prefix + "PF_MEDIAN");
      ObjectDelete(0, g_object_prefix + "PF_UPPER");
      ObjectDelete(0, g_object_prefix + "PF_LOWER");
      return;
     }
   DrawForkLine("MEDIAN", g_t1, g_p1, clrGold, InpDrawForwardBars, STYLE_SOLID);
   DrawForkLine("UPPER", (g_fork_dir > 0 ? g_t2 : g_t3), (g_fork_dir > 0 ? g_p2 : g_p3),
                clrTomato, InpDrawForwardBars, STYLE_DASH);
   DrawForkLine("LOWER", (g_fork_dir > 0 ? g_t3 : g_t2), (g_fork_dir > 0 ? g_p3 : g_p2),
                clrLimeGreen, InpDrawForwardBars, STYLE_DASH);
  }

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
//| Emir acma                                                        |
//+------------------------------------------------------------------+
// Tek bir emir gonderir (mode: 0 = duz magic, 1 = ters magic)
bool SendEntry(const int side, const double entry, const double entry_sl,
               const double entry_tp1, const double entry_tp2, const double atr1,
               const int mode, const string signal_text, const datetime signal_time,
               const double sig_high, const double sig_low)
  {
   double sld = entry_sl;
   double tp1 = entry_tp1;
   double tp2 = entry_tp2;

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

   double nsl = NormalizePriceToTick(sld, (side > 0 ? -1 : 1));
   if(side > 0 && nsl >= entry)
     {
      g_skip_count++;
      g_last_action = "SL giris uzerinde kaldi";
      return false;
     }
   if(side < 0 && nsl <= entry)
     {
      g_skip_count++;
      g_last_action = "SL giris altinda kaldi";
      return false;
     }

   double risk = MathAbs(entry - nsl);
   if(risk <= 0.0)
      return false;
   if(InpMaxSL_ATR > 0.0 && atr1 > 0.0 && risk > InpMaxSL_ATR * atr1)
     {
      g_skip_count++;
      g_last_action = StringFormat("SL cok genis (%.1f x ATR)", risk / atr1);
      PrintFormat("ATLANDI: SL %.1f x ATR | yon=%s", risk / atr1, SideName(side));
      return false;
     }

   long stops_level  = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_distance = MathMax((double)stops_level, (double)freeze_level) * _Point;
   if(risk < min_distance + TickSize())
     {
      g_skip_count++;
      g_last_action = "SL broker minimum mesafesinden kucuk";
      return false;
     }

   double ntp = 0.0;
   if(InpUseFixedTP && tp2 > 0.0)
     {
      ntp = NormalizePriceToTick(tp2, (side > 0 ? -1 : 1));
      if(side * (ntp - entry) < min_distance + TickSize())
        {
         g_skip_count++;
         g_last_action = "TP broker minimum mesafesinden kucuk";
         return false;
        }
     }

   double volume = CalcLot(side, entry, nsl);
   if(volume <= 0.0)
     {
      g_last_action = "Lot hacmi broker sinirlarina uymuyor";
      return false;
     }

   string comment = (side > 0 ? "PF BUY " : "PF SELL ");
   comment += (mode == 1 ? "T" : "D");

   trade.SetExpertMagicNumber(MagicOfMode(mode));
   bool sent = false;
   if(side > 0)
      sent = trade.Buy(volume, _Symbol, 0.0, nsl, ntp, comment);
   else
      sent = trade.Sell(volume, _Symbol, 0.0, nsl, ntp, comment);

   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Giris basarisiz (%s): %s | yon=%s lot=%.8f retcode=%u (%s)",
                  (mode == 1 ? "TERS" : "DUZ"), signal_text, SideName(side), volume,
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
      g_last_action = "Emir broker tarafindan reddedildi";
      return false;
     }

   g_tp1_level[mode] = tp1;
   g_tp2_level[mode] = tp2;
   g_tp1_done[mode]  = false;
   DrawSignalArrow(signal_time, sig_high, sig_low, side);
   PrintFormat("GIRIS (%s): %s | yon=%s | sinyal mumu=%s | lot=%.8f | fiyat=%.*f | SL=%.*f | TP1=%.*f | TP2=%.*f | magic=%I64u",
               (mode == 1 ? "TERS" : "DUZ"), signal_text, SideName(side), TimeToString(signal_time), volume,
               _Digits, entry, _Digits, nsl, _Digits, tp1, _Digits, ntp, MagicOfMode(mode));
   g_last_action = StringFormat("%s %s islem acildi (%s)", SideName(side),
                                (mode == 1 ? "ters" : "duz"), signal_text);
   return true;
  }

//+------------------------------------------------------------------+
//| Sinyal girisi: duz ve/veya ters emirleri acar                    |
//+------------------------------------------------------------------+
bool OpenForkTrade(const int side, const double sl_in, const double tp1_in, const double tp2_in,
                   const double atr1, const string signal_text,
                   const datetime signal_time, const double sig_high, const double sig_low)
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
   double entry = (side > 0 ? tick.ask : tick.bid);
   bool any = false;

   if(ModeNormalOn())
      any = SendEntry(side, entry, sl_in, tp1_in, tp2_in, atr1, 0,
                      signal_text, signal_time, sig_high, sig_low) || any;

   // --- TERS yon plani: yon cevrilir, SL <-> TP2 yer degistirir ---
   if(ModeReverseOn())
     {
      int    rside  = -side;
      double rentry = (rside > 0 ? tick.ask : tick.bid);
      double d_sl = (sl_in > 0.0 ? MathAbs(entry - sl_in) : 0.0);
      double d_t1 = (tp1_in > 0.0 ? MathAbs(tp1_in - entry) : 0.0);
      double d_t2 = (tp2_in > 0.0 ? MathAbs(tp2_in - entry) : 0.0);
      double new_sl_d = (d_t2 > 0.0 ? d_t2 : d_sl);
      double new_t1_d = d_sl;
      double new_t2_d = d_t1;
      double rsl = (new_sl_d > 0.0 ? NormalizePriceToTick(rentry - rside * new_sl_d, (rside > 0 ? -1 : 1)) : 0.0);
      double rt1 = (new_t1_d > 0.0 ? NormalizePriceToTick(rentry + rside * new_t1_d, (rside > 0 ? -1 : 1)) : 0.0);
      double rt2 = (new_t2_d > 0.0 ? NormalizePriceToTick(rentry + rside * new_t2_d, (rside > 0 ? -1 : 1)) : 0.0);
      any = SendEntry(rside, rentry, rsl, rt1, rt2, atr1, 1,
                      signal_text, signal_time, sig_high, sig_low) || any;
     }

   if(!any)
      return false;

   g_signal_count++;
   RefreshDailyCounters();
   return true;
  }

//+------------------------------------------------------------------+
//| Pozisyon yonetimi: TP1 kismi + BE, TP2, kanal kirilimi           |
//+------------------------------------------------------------------+
void ManageForkPositions(const MqlRates &rates[], const double atr1)
  {
   if(CountOurPositions(0) == 0)
     {
      for(int m = 0; m < 2; m++)
        {
         g_tp1_done[m]  = false;
         g_tp1_level[m] = 0.0;
         g_tp2_level[m] = 0.0;
        }
      return;
     }
   if(ArraySize(rates) < 3)
      return;

   double close1 = rates[1].close;
   double tol    = MathMax(InpLineToleranceATR * atr1, _Point * 5.0);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
      if(side == 0)
         continue;
      int    pmode = ModeOfMagic((ulong)PositionGetInteger(POSITION_MAGIC));
      double lvl1  = g_tp1_level[pmode];
      double lvl2  = g_tp2_level[pmode];

      // 1) TP1: median cizgisinde kismi kar + SL'yi BE'ye cek
      if(!g_tp1_done[pmode] && InpPartialClosePercent > 0.0 && lvl1 > 0.0)
        {
         bool hit = (side > 0 ? (close1 >= lvl1) : (close1 <= lvl1));
         if(hit)
           {
            double cur_vol = PositionGetDouble(POSITION_VOLUME);
            double part    = NormalizeVolume(cur_vol * InpPartialClosePercent / 100.0);
            double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            bool done = false;
            if(part > 0.0 && (cur_vol - part) >= step * 0.5)
              {
               if(trade.PositionClosePartial(ticket, part, InpDeviationPoints))
                 {
                  PrintFormat("TP1: kismi kapanis %.2f lot (median) | ticket=%I64u", part, ticket);
                  done = true;
                 }
              }
            else
               done = true;    // kismi kapanis mumkun degil (lot kucuk)
            if(done)
              {
               g_tp1_done[pmode] = true;
               g_last_action = StringFormat("TP1 (median) alindi, %s", 
                                            (InpMoveToBEAfterTP1 ? "SL BE'ye cekildi" : "SL korunuyor"));
               if(InpMoveToBEAfterTP1 && SelectOurPosition(ticket))
                 {
                  double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
                  double cur_tp     = PositionGetDouble(POSITION_TP);
                  double be_sl      = NormalizePriceToTick(open_price, (side > 0 ? 1 : -1));
                  if(trade.PositionModify(ticket, be_sl, cur_tp))
                     PrintFormat("SL BE'ye cekildi (TP1 sonrasi): ticket=%I64u", ticket);
                 }
              }
           }
        }

      // 2) TP2: karsi kanal cizgisi (broker TP yoksa EA kapatir)
      if(lvl2 > 0.0)
        {
         bool hit2 = (side > 0 ? (close1 >= lvl2) : (close1 <= lvl2));
         if(hit2)
           {
            CloseOurPosition(ticket, "TP2 kanal cizgisi");
            continue;
           }
        }

      // 3) Kanal ters yonde kirildi -> duygu degisimi (opsiyonel)
      if(InpExitOnChannelBreak && g_fork_valid)
        {
         double lower1 = ForkLowerAt(1);
         double upper1 = ForkUpperAt(1);
         if(side > 0 && close1 < lower1 - tol)
           {
            CloseOurPosition(ticket, "kanal alt cizgisi kirildi");
            continue;
           }
         if(side < 0 && close1 > upper1 + tol)
           {
            CloseOurPosition(ticket, "kanal ust cizgisi kirildi");
            continue;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Sinyal uretimi (makale Adim 3 veya median retesti)               |
//+------------------------------------------------------------------+
void ProcessForkSignals(const MqlRates &rates[], const double atr1)
  {
   if(!g_fork_valid)
     {
      g_last_action = "3 gecerli pivot (pitchfork) bekleniyor";
      return;
     }
   if(g_t3 <= 2)
     {
      g_last_action = "P3 pivotu henuz kesinlesmedi";
      return;
     }
   if((g_t3 - 1) > InpMaxWaitRetestBars)
     {
      g_last_action = "Kurulum suresi doldu, yeni pitchfork bekleniyor";
      return;
     }

   double tol = MathMax(InpLineToleranceATR * atr1, _Point * 5.0);
   double close1 = rates[1].close;
   double high1  = rates[1].high;
   double low1   = rates[1].low;
   double med1   = ForkMedianAt(1);
   double up1    = ForkUpperAt(1);
   double lo1    = ForkLowerAt(1);
   double buffer = InpSLBufferPips * PipSize();

   // --- 1) Kanal cizgisi ilk retesti ---
   if(InpEntryMode == PF_LINE_RETEST)
     {
      bool already = false, broken = false;
      for(int i = 2; i < g_t3; i++)
        {
         if(g_fork_dir > 0)
           {
            double line = ForkLowerAt(i);
            if(rates[i].close < line - tol)
              {
               broken = true;
               break;
              }
            if(rates[i].low <= line + tol)
              {
               already = true;
               break;
              }
           }
         else
           {
            double line = ForkUpperAt(i);
            if(rates[i].close > line + tol)
              {
               broken = true;
               break;
              }
            if(rates[i].high >= line - tol)
              {
               already = true;
               break;
              }
           }
        }
      if(broken)
        {
         g_last_action = "Kanal cizgisi daha once kirildi, kurulum gecersiz";
         InvalidateFork();
         return;
        }
      if(already)
        {
         g_last_action = "Ilk retest kacirildi (daha once temas edildi)";
         return;
        }

      if(g_fork_dir > 0)
        {
         // ALT destek cizgisinin ilk retesti + cizgi tutuldu
         if(low1 <= lo1 + tol && close1 >= lo1 - tol && close1 > lo1)
           {
            double sl  = lo1 - buffer;
            OpenForkTrade(1, sl, med1, up1, atr1, "Pitchfork alt cizgi retesti",
                          rates[1].time, high1, low1);
            return;
           }
         g_last_action = StringFormat("Alt cizgi retesti bekleniyor (%.*f)", _Digits, lo1);
         return;
        }

      // DUSEN fork: UST direnc cizgisinin ilk retesti
      if(high1 >= up1 - tol && close1 <= up1 + tol && close1 < up1)
        {
         double sl = up1 + buffer;
         OpenForkTrade(-1, sl, med1, lo1, atr1, "Pitchfork ust cizgi retesti",
                       rates[1].time, high1, low1);
         return;
        }
      g_last_action = StringFormat("Ust cizgi retesti bekleniyor (%.*f)", _Digits, up1);
      return;
     }

   // --- 2) Median kirilimi + median retesti ---
   bool broke_up = false, broke_down = false;
   for(int i = 2; i < g_t3; i++)
     {
      double m = ForkMedianAt(i);
      if(rates[i].close > m + tol)
        {
         broke_up = true;
         break;
        }
      if(rates[i].close < m - tol)
        {
         broke_down = true;
         break;
        }
     }

   if(g_fork_dir > 0)
     {
      if(!broke_up)
        {
         g_last_action = "Median uzeri kapanis bekleniyor";
         return;
        }
      if(low1 <= med1 + tol && close1 >= med1 - tol && close1 > med1)
        {
         double sl  = med1 - buffer;
         double tp1 = med1 + (up1 - med1) * 0.5;   // kismi kar: medyan-ust orta nokta
         OpenForkTrade(1, sl, tp1, up1, atr1, "Pitchfork median retesti",
                       rates[1].time, high1, low1);
         return;
        }
      g_last_action = StringFormat("Median retesti bekleniyor (%.*f)", _Digits, med1);
      return;
     }

   if(!broke_down)
     {
      g_last_action = "Median alti kapanis bekleniyor";
      return;
     }
   if(high1 >= med1 - tol && close1 <= med1 + tol && close1 < med1)
     {
      double sl  = med1 + buffer;
      double tp1 = med1 - (med1 - lo1) * 0.5;
      OpenForkTrade(-1, sl, tp1, lo1, atr1, "Pitchfork median retesti",
                    rates[1].time, high1, low1);
      return;
     }
   g_last_action = StringFormat("Median retesti bekleniyor (%.*f)", _Digits, med1);
  }

//+------------------------------------------------------------------+
//| Kapanmis mum isleme                                              |
//+------------------------------------------------------------------+
void ProcessClosedBar()
  {
   int needed = (int)MathMax(150, InpLookbackBars + 60);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, g_tf, 0, needed, rates);
   if(copied < 60)
     {
      g_last_action = StringFormat("Yetersiz mum verisi: %d", copied);
      return;
     }

   double atr1 = 0.0;
   GetATR(1, atr1);

   FindFork(rates);
   DrawFork();

   if(InpLogSignals)
      PrintFormat("PF[%s] fork=%s slope=%.6f med=%.*f up=%.*f lo=%.*f",
                  TimeToString(rates[1].time, TIME_DATE | TIME_MINUTES), ForkName(),
                  g_fork_slope, _Digits, ForkMedianAt(1), _Digits, ForkUpperAt(1),
                  _Digits, ForkLowerAt(1));

   // 1) Pozisyon yonetimi (TP1 / TP2 / kanal kirilimi)
   ManageForkPositions(rates, atr1);

   // 2) Pozisyon aciksa yeni giris yok
   if(CountOurPositions(0) > 0)
     {
      if(g_last_action == "")
         g_last_action = "Pozisyon acik";
      return;
     }

   // 3) Sinyal
   ProcessForkSignals(rates, atr1);
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
      if(InpMoveToBEAtRR > 0.0 && side != 0)
        {
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double cur_sl     = PositionGetDouble(POSITION_SL);
         double risk       = MathAbs(open_price - cur_sl);
         if(risk > 0.0 && cur_sl > 0.0)
           {
            double cur_price = (side > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                        : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
            double moved = side * (cur_price - open_price);
            if(moved >= InpMoveToBEAtRR * risk)
              {
               bool need_move = (side > 0 && cur_sl < open_price) ||
                                (side < 0 && cur_sl > open_price);
               if(need_move)
                 {
                  double be_sl  = NormalizePriceToTick(open_price, (side > 0 ? 1 : -1));
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

   string fork_text = "yok";
   if(g_fork_valid)
      fork_text = StringFormat("%s | P1=%.*f P2=%.*f P3=%.*f | slope=%.5f/bar",
                               ForkName(), _Digits, g_p1, _Digits, g_p2,
                               _Digits, g_p3, g_fork_slope);
   string levels = "yok";
   if(g_fork_valid)
      levels = StringFormat("median=%.*f | ust=%.*f | alt=%.*f",
                            _Digits, ForkMedianAt(1), _Digits, ForkUpperAt(1),
                            _Digits, ForkLowerAt(1));

   Comment("ANDREWS PITCHFORK ROBOT v1.00  [MOD: ", ModeText(), "]", "\n",
           "Sembol: ", _Symbol, " | TF: ", EnumToString(g_tf),
           " | spread: ", DoubleToString((SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                                          SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point, 0),
           " point\n",
           "Mod: ", ModeName(), " | ATR=", DoubleToString(atr1, _Digits), "\n",
           "Pitchfork: ", fork_text, "\n",
           "Seviyeler: ", levels, "\n",
           "Durum: ", StateName(), "\n",
           "TP1 (kismi %", DoubleToString(InpPartialClosePercent, 0), "): ",
           (g_tp1_level[0] > 0.0 ? DoubleToString(g_tp1_level[0], _Digits) : "-"),
           (g_tp1_done[0] ? " [ALINDI]" : ""), "\n",
           "TP2: ", (g_tp2_level[0] > 0.0 ? DoubleToString(g_tp2_level[0], _Digits) : "-"),
           " | SL tampon: ", IntegerToString(InpSLBufferPips), " pip\n",
           "Acik pozisyon B/S: ", IntegerToString(CountOurPositions(1)), "/",
           IntegerToString(CountOurPositions(-1)),
           " | sinyal: ", IntegerToString(g_signal_count),
           " | atlanan: ", IntegerToString(g_skip_count),
           " | bugun: ", IntegerToString(g_trades_today), "\n",
           "Son islem: ", g_last_action);
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
   if(InpPivotStrength < 1 || InpPivotStrength > 8)
     {
      Print("Hatali girdiler: pivot bar sayisi 1-8 arasinda olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLookbackBars < 100 || InpMaxForkAgeBars < 5 || InpMinForkSpanBars < 3 ||
      InpMaxWaitRetestBars < 1)
     {
      Print("Hatali girdiler: bakis >= 100, fork yasi >= 5, span >= 3, retest suresi >= 1 olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLineToleranceATR <= 0.0 || !MathIsValidNumber(InpLineToleranceATR))
     {
      Print("Hatali girdiler: cizgi toleransi pozitif olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpPartialClosePercent < 0.0 || InpPartialClosePercent > 90.0 ||
      !MathIsValidNumber(InpPartialClosePercent))
     {
      Print("Hatali girdiler: kismi kapanis %0-90 arasinda olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpSLBufferPips < 0 || InpSLBufferPips > 200)
     {
      Print("Hatali girdiler: SL tamponu 0-200 pip arasinda olmali (makale: 20-30).");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpSLBufferPips < 20 || InpSLBufferPips > 30)
      Print("BILGI: SL tamponu makalenin 20-30 pip araligi disinda.");
   if(InpLotSize <= 0.0 || !MathIsValidNumber(InpLotSize) ||
      InpRiskPercent <= 0.0 || !MathIsValidNumber(InpRiskPercent))
     {
      Print("Hatali girdiler: lot ve risk % pozitif olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMaxOpenPositions < 0 || InpDeviationPoints < 0 || InpMaxSpreadPoints < 0 ||
      InpMaxPositionMinutes < 0 || InpMaxTradesPerDay < 0 || InpDrawForwardBars < 1)
     {
      Print("Hatali girdiler: sayisal ayarlar negatif olamaz (cizim ileri bar >= 1).");
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

   g_atr_handle = iATR(_Symbol, g_tf, 14);
   if(g_atr_handle == INVALID_HANDLE)
     {
      Print("EA baslatilamadi: ATR gosterge handle olusturulamadi.");
      return INIT_FAILED;
     }

   g_magic_main   = (ulong)InpMagicNumber;
   g_magic_mirror = (InpMagicMirror > 0 ? (ulong)InpMagicMirror : (ulong)InpMagicNumber + 1);
   if(g_magic_mirror == g_magic_main)
      g_magic_mirror = g_magic_main + 1;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_object_prefix = StringFormat("PF_%d_%s_%s_", InpMagicNumber, _Symbol, EnumToString(g_tf));
   g_last_bar_time = iTime(_Symbol, g_tf, 0);
   RefreshDailyCounters();
   InvalidateFork();

   EventSetTimer(1);

   PrintFormat("PITCHFORK ROBOT hazir: %s TF=%s | mod=%s | pivot=%d bakis=%d | SL tampon=%d pip | TP1 kismi=%.0f%%",
               _Symbol, EnumToString(g_tf), ModeName(), InpPivotStrength,
               InpLookbackBars, InpSLBufferPips, InpPartialClosePercent);
   string risk_txt = (InpUseRiskPercent ? DoubleToString(InpRiskPercent, 1) : "KAPALI");
   PrintFormat("Risk: lot=%.2f risk=%s | max SL=%.1f ATR | magic=%d",
               InpLotSize, risk_txt, InpMaxSL_ATR, InpMagicNumber);
   Print("Sinyaller yalnizca KAPANMIS mumlarda degerlendirilir. Acilista gecmise donuk islem acilmaz.");
   PrintFormat(">>> ISLEM MODU: %s | duz magic=%I64u | ters magic=%I64u <<<",
               ModeText(), g_magic_main, g_magic_mirror);
   if(ModeReverseOn())
      Print(">>> TERS ISLEM: BUY sinyalinde SELL, SELL sinyalinde BUY; SL <-> TP2 yer degistirir <<<");
   if(ModeBothOn())
      Print(">>> DUZ+TERS: her sinyalde iki yonde ayri emir acilir; pozisyonlar kendi magic'leriyle ayri yonetilir <<<");
   Print("Akis: 3 pivot -> pitchfork -> kanal/median retesti -> giris | TP1 median (kismi+BE) | TP2 karsi cizgi | SL kanal disi");

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
