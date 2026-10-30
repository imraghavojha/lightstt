import SwiftUI
import AppKit
import Combine

struct LibraryPageView: View {
    @ObservedObject var controller: AppController
    @Environment(\.colorScheme) private var scheme
    @StateObject private var state = LibraryState()

    private var cardColor: Color { scheme == .dark ? Color(red: 60/255, green: 63/255, blue: 67/255) : Color(white: 253/255) }
    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                header
                content
            }
            if state.drawer, let item = controller.selectedHistory {
                Color.black.opacity(0.22).onTapGesture { state.drawer = false }
                metadata(item).frame(width: 300).transition(.move(edge: .trailing))
            }
        }
        .onReceive(Publishers.CombineLatest(controller.$history, controller.$historySearch)) { history, query in
            if CommandLine.arguments.contains("--ui-fixture"), ProcessInfo.processInfo.environment["LIGHTTTS_LIBRARY_STRESS"] == "1", !history.isEmpty, history.count < 5000 {
                let now = Date()
                DispatchQueue.main.async { controller.history = (0..<5000).map { HistoryEntry(text: "Synthetic recording \($0): a sample transcription for scrolling and search.", date: now.addingTimeInterval(Double(-$0 * 60))) } }
            } else { rebuildGroups(history, query: query) }
        }
        .onChange(of: controller.selectedHistory?.id) { _ in state.drawer = false }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Button { controller.leaveLibrary() } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28).background(Color.primary.opacity(0.09), in: Circle()).overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)) }.buttonStyle(.plain)
            Text("Library").font(.system(size: 13, weight: .bold)); Spacer()
            if controller.historySearchVisible {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                    TextField("Search history", text: $controller.historySearch).textFieldStyle(.plain)
                    Button { controller.historySearch = ""; controller.historySearchVisible = false } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                }.font(.system(size: 13)).padding(.horizontal, 8).frame(width: 220, height: 28).background(Color.primary.opacity(0.09), in: Capsule())
            } else {
                Button { controller.historySearchVisible = true } label: { Image(systemName: "magnifyingglass").frame(width: 28, height: 28).background(Color.primary.opacity(0.09), in: Circle()).overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)) }.buttonStyle(.plain).help("Search recordings")
            }
        }.padding(.leading, 12).padding(.trailing, 10).frame(height: 48)
    }
    @ViewBuilder private var content: some View {
            if state.groups.isEmpty {
                VStack { Text(controller.historySearch.isEmpty ? "No recordings yet" : "No recordings found.").font(.system(size: 13)).padding(.top, 133); Spacer() }.frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(state.groups) { group in
                            Text(dayLabel(group.date)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 3).padding(.top, 8)
                            ForEach(group.entries) { item in
                                recording(item)
                            }
                        }
                    }.padding(.leading, 24).padding(.trailing, 33).padding(.top, 20).padding(.bottom, 20)
                }.id(controller.historySearch)
            }
    }
    private func rebuildGroups(_ history: [HistoryEntry], query: String) {
        let entries = query.isEmpty ? history : history.filter { $0.text.localizedCaseInsensitiveContains(query) }
        let grouped = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
        state.groups = grouped.keys.sorted(by: >).map { HistoryGroup(date: $0, entries: grouped[$0]!.sorted { $0.date > $1.date }) }
    }
    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
    private func recording(_ item: HistoryEntry) -> some View {
        let expanded = controller.selectedHistory?.id == item.id
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    controller.stopHistoryPlayback(); controller.historySegmented = false
                    controller.selectedHistory = expanded ? nil : item
                } label: {
                    Text(item.text).lineLimit(expanded ? nil : 2).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if !expanded && controller.hoveredHistoryID == item.id {
                    Menu {
                        Button("Copy") { copy(item) }
                        Button("Delete", role: .destructive) { controller.deleteHistory(item.id) }
                    } label: { Image(systemName: "ellipsis").font(.system(size: 14)) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
            }
            if expanded {
                player(item)
                HStack {
                    HStack(spacing: 0) {
                        segmentButton("Original", selected: !controller.historySegmented) { controller.stopHistoryPlayback(); controller.historySegmented = false }
                        segmentButton("Segmented", selected: controller.historySegmented) { controller.stopHistoryPlayback(); controller.historySegmented = true }.disabled(item.segments?.isEmpty ?? true)
                    }.padding(2).frame(width: 142, height: 28).background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    action("doc.on.doc.fill", "Copy") { copy(item) }
                    Button {} label: { Image(systemName: "sparkle") .overlay(Circle().stroke(lineWidth: 1).frame(width: 12, height: 12)) }.buttonStyle(.plain).disabled(true).help("Process again is not available")
                    action("info.circle", "Recording information") { state.drawer = true }
                    action("trash", "Delete") { controller.deleteHistory(item.id); controller.selectedHistory = nil }
                }.font(.system(size: 12))
                if controller.historySegmented, let segments = item.segments {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        Button { controller.toggleHistoryPlayback(item, segment: segment) } label: {
                            HStack { Image(systemName: "play.fill"); Text("Segment \(index + 1)"); Spacer(); Text("\(duration(segment.start)) – \(duration(segment.end))") }.font(.caption)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(16).background(cardColor, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.05), lineWidth: 0.5))
            .opacity(controller.selectedHistory == nil || expanded ? 1 : 0.55)
            .onHover { hovering in controller.hoveredHistoryID = hovering ? item.id : nil }
            .contextMenu { Button("Copy") { copy(item) }; Button("Delete", role: .destructive) { controller.deleteHistory(item.id); if expanded { controller.selectedHistory = nil } } }
    }
    private func player(_ item: HistoryEntry) -> some View {
        HStack(spacing: 10) {
            Button { controller.toggleHistoryPlayback(item) } label: { Image(systemName: controller.playingHistoryID == item.id ? "pause.fill" : "play.fill") }.buttonStyle(.plain).disabled(controller.historyAudioURL(item) == nil)
            GeometryReader { geometry in
                if let waveform = item.waveform, !waveform.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(Array(waveform.enumerated()), id: \.offset) { _, amplitude in
                            Capsule().fill(Color.primary.opacity(0.55))
                                .frame(width: 1, height: max(2, CGFloat(amplitude) * 20))
                                .frame(width: geometry.size.width / CGFloat(waveform.count))
                        }
                    }.frame(height: geometry.size.height)
                } else {
                    Image(systemName: "waveform").foregroundStyle(.secondary)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }.frame(height: 26).clipped()
            Text(item.recordingDuration.map(duration) ?? "0:00").font(.caption).foregroundStyle(.secondary)
        }.padding(10).background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
    private func segmentButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity).frame(height: 24).background(selected ? (scheme == .dark ? Color.white.opacity(0.18) : Color.white) : .clear, in: RoundedRectangle(cornerRadius: 5)) }.buttonStyle(.plain)
    }
    private func action(_ icon: String, _ help: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Image(systemName: icon).frame(width: 24, height: 24) }.buttonStyle(.plain).help(help)
    }
    private func metadata(_ item: HistoryEntry) -> some View {
        VStack(spacing: 0) {
            HStack {
                action("chevron.left", "Close information") { state.drawer = false }
                Spacer(); Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 13, weight: .bold)); Spacer()
                Color.clear.frame(width: 24, height: 24)
            }.padding(.horizontal, 12).frame(height: 44)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
            VStack(spacing: 12) {
                HStack { Image(systemName: "mic.fill"); Text(item.mode ?? "Not available").fontWeight(.bold); Spacer(); providerBadge }.padding(.horizontal, 14).frame(height: 49).background(cardColor, in: RoundedRectangle(cornerRadius: 14))
                VStack(spacing: 12) {
                    metadataRow("headphones", item.inputName ?? "Not available", item.recordingDuration.map { String(format: "%.1fs", $0) } ?? "—", .pink)
                    metadataRow("provider", item.modelName ?? "Not available", item.processingDuration.map { String(format: "%.0f ms", $0 * 1000) } ?? "—", .purple)
                }.padding(14).background(cardColor, in: RoundedRectangle(cornerRadius: 14))
                Spacer()
                HStack(spacing: 8) {
                    Button("Report issue") { NSWorkspace.shared.open(URL(string: "https://github.com/imraghavojha/lighttts/issues/new")!) }.frame(maxWidth: .infinity, minHeight: 28).background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    Button("Open file location") { controller.revealHistory(item) }.frame(maxWidth: .infinity, minHeight: 28).background(Color.blue, in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(.white)
                }.buttonStyle(.plain).font(.system(size: 11))
            }.padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 16)
        }.frame(maxHeight: .infinity).background(scheme == .dark ? Color(red: 44/255, green: 47/255, blue: 52/255) : Color(white: 0.95)).shadow(color: .black.opacity(0.2), radius: 8, x: -3)
    }
    private func metadataRow(_ icon: String, _ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            if icon == "provider" { providerBadge }
            else { Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.white).frame(width: 20, height: 20).background(color, in: RoundedRectangle(cornerRadius: 5)) }
            Text(title).lineLimit(1); Spacer(minLength: 4); Text(value).font(.caption).foregroundStyle(.secondary)
        }.font(.system(size: 12))
    }
    private var providerBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.15))
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 4).stroke(Color.white, lineWidth: 0.8)
                    .frame(width: 7, height: 13).rotationEffect(.degrees(Double(index) * 60))
            }
        }.frame(width: 20, height: 20)
    }
    private func duration(_ value: Double) -> String { let seconds = max(0, Int(value)); return String(format: "%d:%02d", seconds / 60, seconds % 60) }
    private func copy(_ item: HistoryEntry) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.text, forType: .string) }
}
private struct HistoryGroup: Identifiable { let date: Date; let entries: [HistoryEntry]; var id: Date { date } }

private final class LibraryState: ObservableObject {
    @Published var groups: [HistoryGroup] = []
    @Published var drawer = false
}
