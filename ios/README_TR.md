# Bot Remote iOS — arayüz güncellemesi

Bu paket, gönderilen iOS projesinin üzerine uygulanmış güncellemeleri içerir.

## Eklenenler
- Açık tema varsayılan, koyu tema ve sistem görünümü seçeneği.
- Liquid Glass / Material tabanlı kartlar, yenilenmiş bot listesi ve gösterge paneli.
- Live Activity: aktif bot sayısı, toplam bot sayısı ve bilgisayar bağlantı durumu.
- Dynamic Island: kompakt, minimal ve genişletilmiş görünümler.
- Siri / Kestirmeler: “Bot Remote ile tüm botları başlat”, “Bot Remote ile tüm botları durdur” ve “Bot Remote botları yenile”.
- Bot çevrimiçi olduğunda ve bağlantısı kesildiğinde yerel bildirimler.
- Kullanıcının verdiği bot simgesi AppIcon olarak eklendi.
- Live Activities için `NSSupportsLiveActivities` ve Siri kestirmeleri için URL yönlendirmesi.

## Değiştirilen klasörler / dosyalar
- `ios/BotRemote/App/`
  - `BotRemoteApp.swift`
  - `RootView.swift`
- `ios/BotRemote/Views/`
  - `DashboardView.swift`
  - `Theme.swift`
  - `SettingsView.swift`
  - `ConsoleView.swift`
  - `BotDetailView.swift`
- `ios/BotRemote/Services/`
  - `RemoteStore.swift`
  - Yeni: `NotificationService.swift`
  - Yeni: `BotRemoteShortcuts.swift`
- `ios/BotRemote/Assets.xcassets/AppIcon.appiconset/`
  - `AppIcon.png`
- `ios/BotRemote/info.plist`

## Önemli sınırlar
Bu ZIP yalnızca gönderdiğin iOS projesini içeriyor. Botun Minecraft ekranını gerçekten yakalaması ve her 60 saniyede bir skor tablosu / menüler dahil görüntüyü telefona göndermesi için Windows masaüstü ajanının da ekran yakalama özelliği eklenerek güncellenmesi gerekir. Mevcut iOS paketindeki komut protokolünde ekran görüntüsü olayı veya ekran görüntüsü komutu tanımlı değil; bu yüzden masaüstü ajanı değişmeden bu özelliği çalışıyor gibi göstermek doğru olmaz.

Bildirimler şu anda iOS uygulaması açıkken Socket.IO üzerinden alınan bot durum değişikliklerini yerel bildirime dönüştürür. Uygulama tamamen kapalıyken bildirim alabilmek için sunucunun APNs push bildirimlerini de göndermesi gerekir.

## Derleme
`project.yml` XcodeGen projesidir. Mac üzerinde `xcodegen generate` ardından Xcode ile açıp imzalama ayarlarını yaptıktan sonra derleyebilirsin. Bu ortamda Xcode/iOS SDK bulunmadığı için IPA derlemesi doğrulanmadı.
