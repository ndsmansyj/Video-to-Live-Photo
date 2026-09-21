import SwiftUI

struct HistoryView: View {
    @ObservedObject var library: LiveLibrary
    @State private var search = ""

    private var filtered: [LiveItem] {
        guard !search.isEmpty else { return library.items }
        return library.items.filter {
            $0.baseName.localizedCaseInsensitiveContains(search)
                || $0.detailsText.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("处理历史")
                        .font(.system(size: 28, weight: .bold))
                    Text("查看已经生成的 Live Photo，重新投送或定位文件。")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TextField("搜索文件名", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            .padding(28)

            Divider()

            List(filtered) { item in
                HStack(spacing: 16) {
                    ThumbnailView(url: item.imageURL)
                        .frame(width: 58, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 9))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.baseName)
                            .font(.system(size: 14.5, weight: .semibold))

                        if library.showTechnicalInfo {
                            Text(item.detailsText + " · " + item.durationText)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                        }

                        Text(item.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button("Finder") { library.reveal(item) }

                    Button {
                        library.airdrop([item])
                    } label: {
                        Label("AirDrop", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                .padding(.vertical, 7)
            }
            .listStyle(.inset)
        }
    }
}
