// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// Spending-tab entry row (Paper 10): opens the invoice list and previews the latest invoice.
struct InvoicesEntry: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.themePalette) private var palette
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink { InvoicesView(store: store) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text").foregroundStyle(palette.accent).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Invoices").foregroundStyle(.primary)
                        if let latest = store.invoices?.first {
                            Text("Latest: \(InvoiceText.month(latest)) · \(InvoiceText.total(latest))").font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16).frame(minHeight: 56)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
            }
            .buttonStyle(.plain).accessibilityIdentifier("invoicesEntry")
            Text("Invoices include tax and discounts. The consumption estimates above do not.")
                .font(.footnote).foregroundStyle(Theme.muted).padding(.horizontal, 4)
        }
        .task { if store.invoices == nil { await store.loadInvoices() } }
    }
}

struct InvoicesView: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.themePalette) private var palette
    var body: some View {
        List {
            if let error = store.invoicesError {
                Section { InlineFailure(message: error, lastSuccess: nil) { Task { await store.loadInvoices() } } }
            }
            if let invoices = store.invoices {
                if invoices.isEmpty {
                    ContentUnavailableView("No invoices yet", systemImage: "doc.text", description: Text("Invoices appear here after each billing month closes."))
                } else {
                    Section {
                        ForEach(invoices) { invoice in
                            NavigationLink { InvoiceDetailView(store: store, invoice: invoice) } label: { InvoiceRow(invoice: invoice) }
                        }
                    } footer: { Text("Amounts include tax. Open an invoice to see discounts or share the PDF.") }
                }
            } else if store.invoicesError == nil {
                ProgressView("Loading invoices…").frame(maxWidth: .infinity)
            }
        }
        .scrollContentBackground(.hidden).background(palette.canvas)
        .navigationTitle("Invoices").navigationBarTitleDisplayMode(.large)
        .refreshable { await store.loadInvoices() }
        .task { if store.invoices == nil { await store.loadInvoices() } }
    }
}

private struct InvoiceRow: View {
    let invoice: Invoice
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(InvoiceText.month(invoice))
                HStack(spacing: 8) {
                    InvoiceBadge(invoice: invoice)
                    if let number = invoice.number { Text("No. \(String(number))").font(.footnote).foregroundStyle(Theme.muted) }
                }
            }
            Spacer(minLength: 8)
            Text(InvoiceText.total(invoice)).monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct InvoiceBadge: View {
    let invoice: Invoice
    @Environment(\.themePalette) private var palette
    var body: some View {
        let paid = invoice.state.lowercased() == "paid"
        let color = paid ? Theme.success : palette.accent
        Text(InvoiceText.status(invoice))
            .font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 1)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct InvoiceDetailView: View {
    @ObservedObject var store: DashboardStore
    let invoice: Invoice
    @State private var pdf: SharedFile?
    @State private var tempFile: URL?
    @State private var downloading = false
    @State private var downloadError: String?
    @Environment(\.themePalette) private var palette
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        InvoiceBadge(invoice: invoice)
                        if let number = invoice.number { Text("No. \(String(number))").font(.footnote).foregroundStyle(Theme.muted) }
                    }
                    Text(InvoiceText.total(invoice)).font(.system(.largeTitle, weight: .semibold)).monospacedDigit().padding(.top, 4)
                    Text(issuedLine).font(.footnote).foregroundStyle(Theme.muted)
                }.padding(.vertical, 8)
            }
            Section {
                row("Before discount", invoice.totalUndiscount ?? invoice.totalUntaxed)
                if let discount = invoice.totalDiscount, discount.amount != 0 {
                    LabeledContent("Discounts") {
                        Text("−" + discount.amount.formatted(.currency(code: discount.currency))).foregroundStyle(Theme.success)
                    }
                }
                row("Tax", invoice.totalTax)
                row("Total", invoice.totalTaxed).fontWeight(.semibold)
            }
            Section {
                Button {
                    Task { await download() }
                } label: {
                    HStack { Label("Share PDF", systemImage: "square.and.arrow.up"); if downloading { Spacer(); ProgressView() } }
                }
                .buttonStyle(SolidPrimaryButton()).disabled(downloading).accessibilityIdentifier("shareInvoicePDF")
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                if let downloadError {
                    Label(downloadError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                }
            }
        }
        .sheet(item: $pdf, onDismiss: removeTempFile) { file in
            ShareSheet(url: file.url).presentationDetents([.medium, .large])
        }
        .scrollContentBackground(.hidden).background(palette.canvas)
        .navigationTitle(InvoiceText.month(invoice)).navigationBarTitleDisplayMode(.large)
        .onDisappear(perform: removeTempFile)
    }
    private func download() async {
        downloading = true; downloadError = nil
        defer { downloading = false }
        do {
            let url = try await store.invoicePDF(id: invoice.id)
            tempFile = url; pdf = SharedFile(url: url)
        }
        catch { downloadError = ((error as? APIError) ?? .network).localizedDescription }
    }
    // The sheet clears `pdf` before onDismiss runs, so the path is kept separately.
    private func removeTempFile() {
        if let tempFile { try? FileManager.default.removeItem(at: tempFile) }
        tempFile = nil
    }
    private var issuedLine: String {
        guard let issued = invoice.issuedDate else { return "Total including tax" }
        return "Total including tax · issued \(issued.formatted(date: .abbreviated, time: .omitted))"
    }
    @ViewBuilder private func row(_ title: String, _ money: APIMoney?) -> some View {
        if let money { LabeledContent(title, value: money.amount.formatted(.currency(code: money.currency))) }
    }
}

enum InvoiceText {
    static func month(_ invoice: Invoice) -> String {
        invoice.billingMonth.map { BillingSummary.monthLabel($0) } ?? invoice.issuedDate?.formatted(date: .abbreviated, time: .omitted) ?? "Invoice"
    }
    static func total(_ invoice: Invoice) -> String {
        guard let total = invoice.totalTaxed else { return "—" }
        return total.amount.formatted(.currency(code: total.currency))
    }
    static func status(_ invoice: Invoice) -> String {
        if invoice.state.lowercased() == "paid" { return "Paid" }
        if let due = invoice.dueDate { return "Due \(due.formatted(.dateTime.day().month(.abbreviated)))" }
        return invoice.state.isEmpty ? "Issued" : invoice.state.capitalized
    }
}

struct SharedFile: Identifiable { let url: URL; var id: URL { url } }

/// UIKit share sheet for a downloaded file; SwiftUI's ShareLink needs the file before the tap.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
