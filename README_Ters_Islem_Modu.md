# Ters İşlem Modu (Reverse Mode) — 5 Bot için Ortak Özellik

Bu doküman, projedeki **tüm strateji botlarına** eklenen `InpReverseMode` özelliğini tek yerden açıklar.

| Bot | Dosya | Magic | Ters mod desteği |
|---|---|---|---|
| CCI Trading System | `CCI_Trading_System.mq5` | 20261116 | ✅ |
| Rectangle Pattern | `Rectangle_Pattern_Bot.mq5` | 20261117 | ✅ |
| S/R Bounce | `Bounce_Trading_Bot.mq5` | 20261118 | ✅ (limit ↔ stop dahil) |
| AO Twin Peaks | `AO_TwinPeaks_Bot.mq5` | 20261119 | ✅ |
| Andrews Pitchfork | `AndrewsPitchfork_Bot.mq5` | 20261120 | ✅ (TP1/TP2 dahil) |

## 1. Ne yapar?

`InpReverseMode = true` iken bot **aynı sinyalleri ters yönde işler**. Sinyal üretim mantığı, trend/spread/saat filtreleri ve seviye hesapları **hiç değişmez**; sadece emir gönderilirken yön ve koruma seviyeleri çevrilir.

| Konu | Normal | Ters mod |
|---|---|---|
| BUY sinyali | BUY | **SELL** |
| SELL sinyali | SELL | **BUY** |
| Stop Loss | stratejinin SL'si | **eski TP mesafesinde** (girişin diğer tarafı) |
| Take Profit | stratejinin TP'si | **eski SL mesafesinde** |
| TP'siz (gösterge çıkışlı) stratejilerde SL | swing/kanal + tampon | girişe göre **aynalanır** |
| Bekleyen emir tipi (S/R Bounce) | limit / stop | **limit ↔ stop** |
| Kısmi kâr (Pitchfork) | TP1 (median) + TP2 (karşı çizgi) | SL ↔ TP2 yer değişir, TP1 = SL mesafesi |

Ek olarak: `InpAllowLongs` / `InpAllowShorts` ve `InpMaxSL_ATR` gibi risk filtreleri **işleme girecek gerçek yöne** uygulanır; panel başlığında `[TERS ISLEM MODU]` görünür ve uzman günlüğüne uyarı basılır.

## 2. Örnek (Piyasa emri)

Orijinal BUY sinyali: `entry = 1.10000`, `SL = 1.09800 (−20 pip)`, `TP = 1.10400 (+40 pip)`

Ters modda:
- yön → **SELL**
- `SL = 1.10400` (eski TP mesafesi 40 pip, SELL'de girişin üstünde)
- `TP = 1.09800` (eski SL mesafesi 20 pip, SELL'de girişin altında)

Yani kâr/zarar seviyeleri giriş fiyatı etrafında **aynalanır**.

## 3. Bekleyen emirler (yalnızca S/R Bounce)

Ayna simetrisi gereği emir tipi de çevrilir:

| Orijinal | Ters mod |
|---|---|
| `BUY_LIMIT` (destek üstünde al) | `SELL_STOP` (desteği kırınca sat) |
| `SELL_LIMIT` (direnç altında sat) | `BUY_STOP` (direnci kırınca al) |
| `BUY_STOP` (direnç kırılımı al) | `SELL_LIMIT` (dirençte sat) |
| `SELL_STOP` (destek kırılımı sat) | `BUY_LIMIT` (destekte al) |

Seviye (`price`) değişmez; SL/TP mesafeleri yer değiştirir; BE (başabaş) takibi için planlanan SL mesafesi de düzeltilir.

## 4. Nasıl açılır?

1. MT5 → **Uzman Danışmanlar** özelliklerinde `InpReverseMode` parametresini seçin.
2. Hazır `.set` dosyalarının tamamında bu parametre `false` gelir; ters mod için `true` yapın.
3. Strateji Tester'da normal ve ters modu **aynı veri/spread** ile karşılaştırarak test edin.

## 5. Uyarılar

- ⚠️ **Risk/ödül tersine döner:** 20 pip SL / 40 pip TP kullanan bir strateji ters modda 40 pip SL / 20 pip TP olur. Ortalama kazanç artarken kazanma oranı düşer.
- Ters modda SL mesafesi orijinalin TP mesafesi olduğu için `InpMaxSL_ATR` filtresi normalden sık devreye girebilir; gerekirse gevşetin.
- Gösterge tabanlı çıkışlar (CCI seviyeleri, AO renk dönüşü, bant/kanal ihlali) pozisyonun gerçek yönüne göre otomatik ters çalışır; ayrı bir ayar gerekmez.
- Rectangle botunda "dikdörtgene geri dönüş" çıkışı (`InpCloseOnReenter`) ters modda **devre dışıdır**: kırılımın başarısız olması ters pozisyonun lehine olduğu için bu çıkış mantığı geçersizdir.
- Bu mod, bir stratejinin gerçekten **kenar (edge) taşıyıp taşımadığını** test etmek ya da aynı kurulumları **ters piyasa rejiminde** kullanmak için tasarlanmıştır; tek başına "kâr garantisi" değildir.

## 6. Kod tarafı (özet)

Her botta sinyal → emir fonksiyonunun (`OpenTrade` / `OpenSignal` / `OpenForkTrade` / `PlacePendingOrder`) başında tek bir ters çevirme bloğu vardır:

```mql5
input bool InpReverseMode = false; // TERS ISLEM MODU

...
double d_sl = (sl > 0.0 ? MathAbs(entry - sl) : 0.0);
double d_tp = (tp > 0.0 ? MathAbs(tp - entry) : 0.0);
side = -side;
sl = NormalizePriceToTick(entry - side * new_sl_dist, ...); // eski TP mesafesi
tp = NormalizePriceToTick(entry + side * d_sl, ...);         // eski SL mesafesi
```

Böylece lot hesabı (`CalcLot`), SL mesafesi filtreleri, kısmi kâr (TP1→BE) ve panel/log çıktıları **tek noktadan** tutarlı şekilde ters moda uyar.
