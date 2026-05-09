import SwiftUI

/// Paginated credit ledger backed by `GET /api/credits/transactions/me`.
/// Shows only the three fields the user asked for: time, reason, amount (signed).
struct CreditHistoryView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var shenma: ShenmaConnectionManager
    @EnvironmentObject var l10n: LocalizationManager

    let close: () -> Void

    @State private var items: [CreditTransaction] = []
    @State private var page: Int = 1
    private let pageSize: Int = 20
    @State private var hasMore: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    Label(l10n.t("common.back"), systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                Text(l10n.t("credits.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let balance = shenma.creditBalance {
                    Text(l10n.t("popover.creditBalance", balance))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    if items.isEmpty && !isLoading && errorMessage == nil {
                        Text(l10n.t("credits.empty"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    }
                    ForEach(items) { row in
                        CreditRow(transaction: row, dateFormatter: Self.dateFormatter)
                        Divider().opacity(0.5)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.vertical, 12)
                    } else if hasMore {
                        Button(l10n.t("credits.loadMore")) {
                            Task { await loadMore() }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .task {
            // First-page load whenever the view appears. Reset state so revisiting
            // the page after disconnect/reconnect doesn't keep stale rows.
            items = []
            page = 1
            hasMore = false
            errorMessage = nil
            await loadMore()
        }
    }

    private func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await shenma.fetchTransactions(
                baseUrl: settings.shenmaBaseUrl,
                page: page,
                size: pageSize
            )
            items.append(contentsOf: response.items)
            hasMore = response.hasMore
            page += 1
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CreditRow: View {
    @EnvironmentObject var l10n: LocalizationManager
    let transaction: CreditTransaction
    let dateFormatter: DateFormatter

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateFormatter.string(from: transaction.createdAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(displayReason)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            Spacer()
            Text(formattedAmount)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(transaction.amount >= 0 ? .green : .red)
        }
        .padding(.vertical, 8)
    }

    /// Translate strictly off the backend's `type` enum — never surface the
    /// freeform `reason` string (it's a stable code-like ID like "ai_generation"
    /// that's not user-facing) or the raw enum constant. Unknown types fall back
    /// to a localized generic label rather than leaking the code through.
    private var displayReason: String {
        let key = "credits.type.\(transaction.type.uppercased())"
        let translated = l10n.t(key)
        if translated != key { return translated }
        return l10n.t("credits.type.unknown")
    }

    private var formattedAmount: String {
        let sign = transaction.amount >= 0 ? "+" : ""
        return "\(sign)\(transaction.amount)"
    }
}
