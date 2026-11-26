import SwiftUI
import UIKit

struct SavedScreenshot: Codable, Identifiable, Equatable {
    var id: String
    var botId: String
    var botName: String
    var serverAddress: String
    var capturedAt: Double
    var fileName: String

    var date: Date { Date(timeIntervalSince1970: capturedAt / 1000) }
}

@MainActor
final class ScreenshotArchive: ObservableObject {
    static let shared = ScreenshotArchive()

    @Published private(set) var records: [SavedScreenshot] = []
    private let maximumStoredImages = 400
    private let folderName = "BotRemoteScreenshots"

    private init() {
        createFolderIfNeeded()
        loadIndex()
    }

    private var folderURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    private var indexURL: URL { folderURL.appendingPathComponent("index.json") }

    func store(_ snapshot: BotScreenSnapshot, botId: String) {
        createFolderIfNeeded()

        let view = MinecraftScreenImage(snapshot: snapshot)
            .frame(width: 1200, height: 760)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1

        guard let image = renderer.uiImage,
              let data = image.jpegData(compressionQuality: 0.78) else { return }

        let identifier = UUID().uuidString
        let fileName = identifier + ".jpg"
        let imageURL = folderURL.appendingPathComponent(fileName)

        do {
            try data.write(to: imageURL, options: .atomic)
            let record = SavedScreenshot(
                id: identifier,
                botId: botId,
                botName: snapshot.botName,
                serverAddress: snapshot.serverAddress,
                capturedAt: snapshot.capturedAt,
                fileName: fileName
            )
            records.insert(record, at: 0)
            trimOldRecords()
            saveIndex()
        } catch {
            // A full device or unavailable storage must not interrupt bot control.
        }
    }

    func image(for record: SavedScreenshot) -> UIImage? {
        UIImage(contentsOfFile: folderURL.appendingPathComponent(record.fileName).path)
    }

    func delete(_ record: SavedScreenshot) {
        let url = folderURL.appendingPathComponent(record.fileName)
        try? FileManager.default.removeItem(at: url)
        records.removeAll { $0.id == record.id }
        saveIndex()
    }

    func deleteAll() {
        for record in records {
            try? FileManager.default.removeItem(at: folderURL.appendingPathComponent(record.fileName))
        }
        records.removeAll()
        saveIndex()
    }

    private func createFolderIfNeeded() {
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([SavedScreenshot].self, from: data) else {
            records = []
            return
        }
        records = decoded
            .filter { FileManager.default.fileExists(atPath: folderURL.appendingPathComponent($0.fileName).path) }
            .sorted { $0.capturedAt > $1.capturedAt }
        trimOldRecords()
        saveIndex()
    }

    private func trimOldRecords() {
        guard records.count > maximumStoredImages else { return }
        let removed = Array(records.dropFirst(maximumStoredImages))
        for record in removed {
            try? FileManager.default.removeItem(at: folderURL.appendingPathComponent(record.fileName))
        }
        records = Array(records.prefix(maximumStoredImages))
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}

struct MinecraftScreenImage: View {
    let snapshot: BotScreenSnapshot

    private var displayedSlots: [ScreenSlot] {
        snapshot.window?.slots ?? snapshot.inventory
    }
    private var slotCount: Int {
        snapshot.window == nil ? 36 : 54
    }
    private var slotsByIndex: [Int: ScreenSlot] {
        Dictionary(displayedSlots.map { ($0.slot, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        ZStack {
            Color(hex: 0x101820)
            VStack(spacing: 0) {
                header
                HStack(alignment: .top, spacing: 18) {
                    gamePanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    scoreboardPanel
                        .frame(width: 270)
                }
                .padding(18)
                footer
            }
            .padding(18)
        }
        .frame(width: 1200, height: 760)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(hex: 0x9EDB72))
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.botName.uppercased())
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("\(snapshot.username)  •  \(snapshot.serverAddress)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xAAB8C2))
            }
            Spacer()
            Text(snapshot.date.formatted(date: .abbreviated, time: .standard))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: 0xB7C5CE))
            Circle().fill(Color(hex: 0x73D38B)).frame(width: 8, height: 8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(hex: 0x202D37))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var gamePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(snapshot.window?.title.isEmpty == false ? snapshot.window!.title : "OYUNCU ENVANTERİ")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Text(snapshot.window?.type ?? "minecraft:inventory")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x8DA2B1))
                    .lineLimit(1)
            }

            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                ForEach(0..<((slotCount + 8) / 9), id: \.self) { row in
                    GridRow {
                        ForEach(0..<9, id: \.self) { column in
                            let index = row * 9 + column
                            if index < slotCount { slotCell(index) }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Label(snapshot.window == nil ? "GUI açık değil" : "Açık arayüz", systemImage: "rectangle.3.group")
                Text("•")
                Text("Yalnızca bot arayüz verisi")
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(hex: 0x90A3AF))
        }
        .padding(15)
        .background(Color(hex: 0x26333D), in: RoundedRectangle(cornerRadius: 10))
    }

    private var scoreboardPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "list.number")
                    .foregroundStyle(Color(hex: 0xF1D477))
                Text("SCOREBOARD")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            Text(snapshot.scoreboard?.title.isEmpty == false ? snapshot.scoreboard!.title : "Scoreboard yok")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: 0xF1D477))
                .lineLimit(2)
            if let scoreboard = snapshot.scoreboard, !scoreboard.rows.isEmpty {
                ForEach(Array(scoreboard.rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 8) {
                        Text("\(index + 1).")
                            .foregroundStyle(Color(hex: 0x7F929F))
                            .frame(width: 20, alignment: .leading)
                        Text(row.name)
                            .foregroundStyle(Color(hex: 0xE4E9ED))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text("\(row.value)")
                            .foregroundStyle(Color(hex: 0xF1D477))
                            .monospacedDigit()
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Divider().overlay(Color(hex: 0x43515C))
                }
            } else {
                Text("Sunucudan scoreboard bilgisi gelmedi.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x9AABB5))
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: 0x202D37), in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack {
            Text("BOT REMOTE  /  GUI SNAPSHOT")
            Spacer()
            Text("MINEFLAYER DATA  •  60s INTERVAL")
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(Color(hex: 0x8295A2))
        .padding(.horizontal, 5)
        .padding(.top, 4)
    }

    private func slotCell(_ index: Int) -> some View {
        let slot = slotsByIndex[index]
        return VStack(spacing: 3) {
            Image(systemName: symbol(for: slot?.itemName ?? ""))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(slot == nil ? Color(hex: 0x52616D) : Color(hex: 0xE2E9EE))
            Text(slot.map { shortName($0.name) } ?? "")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: 0xC3D0D8))
                .lineLimit(1)
            if let slot, slot.count > 1 {
                Text("×\(slot.count)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xF7D77B))
            }
        }
        .frame(width: 55, height: 55)
        .background(Color(hex: 0x303D47), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(hex: 0x53626D), lineWidth: 1))
    }

    private func shortName(_ value: String) -> String {
        let clean = value.replacingOccurrences(of: "minecraft:", with: "")
        return String(clean.prefix(10))
    }

    private func symbol(for item: String) -> String {
        let name = item.lowercased()
        if name.contains("sword") { return "sword.fill" }
        if name.contains("pickaxe") || name.contains("axe") || name.contains("shovel") { return "hammer.fill" }
        if name.contains("bow") || name.contains("arrow") { return "arrow.up.right" }
        if name.contains("food") || name.contains("apple") || name.contains("bread") { return "leaf.fill" }
        if name.contains("potion") { return "drop.fill" }
        if name.contains("helmet") || name.contains("chestplate") || name.contains("boots") { return "shield.fill" }
        if name.contains("map") || name.contains("compass") { return "map.fill" }
        return "cube.fill"
    }
}

struct GalleryView: View {
    @StateObject private var archive = ScreenshotArchive.shared
    @State private var searchText = ""
    @State private var confirmDeleteAll = false

    private var filteredRecords: [SavedScreenshot] {
        guard !searchText.isEmpty else { return archive.records }
        return archive.records.filter {
            $0.botName.localizedCaseInsensitiveContains(searchText) ||
            $0.serverAddress.localizedCaseInsensitiveContains(searchText)
        }
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if archive.records.isEmpty {
                    EmptyState(
                        icon: "photo.on.rectangle.angled",
                        title: "Henüz ekran görüntüsü yok",
                        text: "Çevrimiçi botların Minecraft arayüzleri her dakika burada biriktirilir."
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(filteredRecords) { record in
                                NavigationLink {
                                    ScreenshotDetailView(record: record)
                                } label: {
                                    ScreenshotTile(record: record)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)
                    }
                }
            }
            .navigationTitle("Galeri")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Bot veya sunucu ara")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Galeriyi temizle", role: .destructive) { confirmDeleteAll = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(archive.records.isEmpty)
                }
            }
            .confirmationDialog("Galerideki tüm görüntüler silinsin mi?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Tümünü sil", role: .destructive) { archive.deleteAll() }
            } message: {
                Text("Bu işlem telefonda saklanan ekran görüntülerini siler.")
            }
            .overlay(alignment: .bottom) {
                if !archive.records.isEmpty {
                    Text("Son \(archive.records.count) görüntü · en eski görüntüler otomatik temizlenir")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 8)
                }
            }
        }
    }
}

private struct ScreenshotTile: View {
    @StateObject private var archive = ScreenshotArchive.shared
    let record: SavedScreenshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if let image = archive.image(for: record) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.cardHigh)
                        .overlay(Image(systemName: "photo").foregroundStyle(Theme.muted))
                }
            }
            .frame(height: 112)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(record.botName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(record.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(Theme.muted)
            Text(record.serverAddress)
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .padding(9)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ScreenshotDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var archive = ScreenshotArchive.shared
    let record: SavedScreenshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let image = archive.image(for: record) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    EmptyState(icon: "photo", title: "Görüntü bulunamadı", text: "Dosya silinmiş olabilir.")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(record.botName).font(.title3.weight(.bold))
                    Text(record.serverAddress).font(.subheadline).foregroundStyle(Theme.muted)
                    Text(record.date.formatted(date: .complete, time: .standard))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                Button(role: .destructive) {
                    archive.delete(record)
                    dismiss()
                } label: {
                    Label("Görüntüyü sil", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Ekran görüntüsü")
        .navigationBarTitleDisplayMode(.inline)
    }
}
