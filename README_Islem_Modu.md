# İşlem Modu: Düz / Ters / Düz + Ters — 5 Bot için Ortak Özellik

Bu doküman, projedeki **tüm strateji botlarında** bulunan `InpTradeMode` ayarını tek yerden açıklar.

| Bot | Dosya | Ana magic | Ters magic | Düz + Ters |
|---|---|---|---|---|
| CCI Trading System | `CCI_Trading_System.mq5` | 20261116 | 20261117* | ✅ |
| Rectangle Pattern | `Rectangle_Pattern_Bot.mq5` | 20261117 | 20261118* | ✅ |
| S/R Bounce | `Bounce_Trading_Bot.mq5` | 20261118 | 20261119* | ✅ |
| AO Twin Peaks | `AO_TwinPeaks_Bot.mq5` | 20261119 | 20261120* | ✅ |
| Andrews Pitchfork | `Andrews_Pitchfork_Bot.mq5` / `AndrewsPitchfork_Bot.mq5` | 20261120 | 20261121* | ✅ |

\* Varsayılan ters magic = `InpMagicNumber + 1`. Botların magic numaraları birbirine bitişik olduğu için **aynı hesapta birden fazla bot çalıştıracaksanız `InpMagicMirror` değerini elle** çakışmayacak şekilde ayarlayın (ör. 20261116 → 30261116).

## 1. Tek ayar, üç mod

```mql5
input ENUM_TRADE_MODE InpTradeMode  = TRADE_MODE_NORMAL; // 0=duz 1=ters 2=duz+ters
input int             InpMagicMirror = 0;                // 0 = InpMagicNumber+1
```

| `InpTradeMode` | Mod | Davranış |
|---|---|---|
| `0` | **Düz** | Sinyal yönünde tek emir (klasik davranış) |
| `1` | **Ters** | BUY sinyali → SELL, SELL sinyali → BUY; SL/TP mesafeleri yer değiştirir |
| `2` | **Düz + Ters** | Her sinyalde **iki emir**: düz emir ana magic, ters emir ikinci magic ile açılır. İki taraf tamamen ayrı yönetilir. |

## 2. Düz + Ters modunda pozisyonlar nasıl ayrı yönetilir?

- **Magic ayrımı:** düz işlemler `InpMagicNumber`, ters işlemler `InpMagicMirror` magic'ini taşır. Botun tüm pozisyon/emir tarama fonksiyonları iki magic'i de tanır.
- **Yön, pozisyondan okunur:** çıkış kuralları (CCI seviyeleri, AO renk dönüşü, kanal/çizgi ihlali, dikdörtgene dönüş, para TP/SL, süre sınırı) her pozisyonun **kendi yönüne** göre değerlendirilir. Bu sayede aynı anda açık bir LONG ve bir SHORT pozisyon birbirinin kuralını çalıştırmaz.
- **Plan verileri mod bazında:** başabaş takibi (`InpMoveToBEAtRR`) ve Pitchfork'un TP1/TP2 + kısmi kâr seviyeleri `[0] = düz`, `[1] = ters` olarak ayrı saklanır. `g_planned_*[mode]`, `g_tp1_level[mode]`, `g_tp2_level[mode]`, `g_tp1_done[mode]`.
- **Pozisyon limiti:** `InpMaxOpenPositions` mod 2'de **yön başına** uygulanır (1 → en fazla 1 düz + 1 ters). Tek modlarda eski anlam korunur (toplam pozisyon).
- **Lot/risk:** her emir kendi SL mesafesiyle `CalcLot` üzerinden hesaplanır; ters tarafta SL mesafesi farklı olduğu için lot da farklı çıkabilir (risk yüzdesi modu kullanılıyorsa iki taraf da aynı riski taşır).
- **Sinyal üretimi tektir:** sinyal, trend, spread, saat ve günlük limit filtreleri bir kez çalışır; iki emir aynı sinyalden doğar (dolayısıyla `g_trades_today` sinyal başına bir artar).

## 3. SL/TP aynalaması

| Konu | Düz taraf | Ters taraf |
|---|---|---|
| Yön | BUY → BUY, SELL → SELL | BUY → SELL, SELL → BUY |
| Stop Loss | stratejinin SL'si | **eski TP mesafesinde** |
| Take Profit | stratejinin TP'si | **eski SL mesafesinde** |
| TP'siz stratejiler | SL + gösterge çıkışı | SL aynalanır; gösterge çıkışı ters yönde çalışır |
| Bekleyen emir (Bounce) | limit / stop | **limit ↔ stop** |
| Kısmi kâr (Pitchfork) | TP1 (median) + TP2 (karşı çizgi) | SL ↔ TP2 yer değişir, TP1 = SL mesafesi |

Örnek — orijinal BUY sinyali: `entry = 1.10000`, `SL = 1.09800 (−20 pip)`, `TP = 1.10400 (+40 pip)`

- Düz taraf: BUY, SL 1.09800, TP 1.10400
- Ters taraf: **SELL**, SL **1.10400**, TP **1.09800** (giriş etrafında ayna)

## 4. Bekleyen emirlerde aynalama (yalnızca S/R Bounce)

| Orijinal | Ters |
|---|---|
| `BUY_LIMIT` (destek üstünde al) | `SELL_STOP` (desteği kırınca sat) |
| `SELL_LIMIT` (direnç altında sat) | `BUY_STOP` (direnci kırınca al) |
| `BUY_STOP` (direnç kırılımı al) | `SELL_LIMIT` (dirençte sat) |
| `SELL_STOP` (destek kırılımı sat) | `BUY_LIMIT` (destekte al) |

Seviye (`price`) değişmez; SL/TP mesafeleri yer değiştirir. Mod 2'de böylece aynı bölgede hem "sekme" hem "kırılım" tarafı bekler.

## 5. Nasıl kullanılır?

1. Botu grafiğe ekleyin → **Girdiler** → `InpTradeMode`:
   - `0` düz, `1` ters, `2` düz + ters.
2. Mod 2 kullanacaksanız `InpMagicMirror` çakışmasına dikkat edin (aşağıdaki uyarı).
3. Panelde `[MOD: DUZ]`, `[MOD: TERS]`, `[MOD: DUZ+TERS]` görünür; günlükte mod ve iki magic yazdırılır.
4. Strateji Tester'da mod 0 / 1 / 2 sonuçlarını aynı veri ve spread ile karşılaştırın.

## 6. Uyarılar

- ⚠️ **Magic çakışması:** varsayılan ters magic `magic + 1`'dir. Farklı botların magic'leri bitişik olduğu için aynı hesapta iki bot mod 2 ile çalışacaksa `InpMagicMirror` değerlerini elle ayırın.
- ⚠️ **Risk/ödül tersine döner:** ters tarafta SL orijinalin TP'si, TP orijinalin SL'si olur; kazanma oranı düşer, ortalama kazanç artar.
- ⚠️ **`InpMaxSL_ATR` filtresi** ters tarafta daha sık devreye girebilir (SL mesafesi büyük); gerekirse gevşetin.
- ⚠️ **Rectangle botunda** "dikdörtgene geri dönüş" çıkışı (`InpCloseOnReenter`) yalnızca **düz** pozisyonlara uygulanır.
- ⚠️ **Mod değiştirmeden önce açık pozisyonları kapatın.** Mod 2'den çıkıldığında ikinci magic'li pozisyonlar yönetilmeye devam eder ama başabaş/kısmi kâr referansları geçersiz kalır.
- Mod 2 iki kat emir, iki kat komisyon/spread demektir; net kâr hesabında bunu unutmayın.

## 7. Kod tarafı (özet)

```mql5
ulong g_magic_main, g_magic_mirror;

bool  ModeNormalOn()  { return (InpTradeMode == TRADE_MODE_NORMAL  || InpTradeMode == TRADE_MODE_BOTH); }
bool  ModeReverseOn() { return (InpTradeMode == TRADE_MODE_REVERSE || InpTradeMode == TRADE_MODE_BOTH); }
ulong MagicOfMode(const int mode) { return (mode == 1 && ModeBothOn() ? g_magic_mirror : g_magic_main); }

// giris: sinyal bir kez uretilir, iki yon icin emir gonderilir
if(ModeNormalOn())  SendEntry(side,  entry,  sl,      tp,      0, ...);
if(ModeReverseOn()) SendEntry(-side, rentry,  mirror_sl, mirror_tp, 1, ...);
```

- `SelectOurPosition()` / `CountOurPending()` / `DeleteOurPending()` / deal-history sayaçları `IsOurMagic()` ile iki magic'i de kapsar.
- Her emirden önce `trade.SetExpertMagicNumber(MagicOfMode(mode))` çağrılır.
- Emir yorumları `D` (düz) / `T` (ters) sonekiyle ayrılır: `CCI BUY D`, `CCI BUY T`, `BOUNCE SELL LMT T`, …
