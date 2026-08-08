import SwiftUI
import PhotosUI
import Capture
import UI

// UIImage's orientation enum and CGImagePropertyOrientation disagree on
// raw values — this is Apple's documented mapping, needed to tell Vision
// which way the photo actually points.
extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// MARK: - ReceiptCaptureView (blueprint Phase 2.2)
// Photo → on-device OCR → pre-filled form → user confirms → write.
// The review step is mandatory by design: OCR output is never trusted
// silently. Uses the photo library picker (photograph the receipt with the
// Camera app, then pick it); an in-app camera button can join in the
// Phase 6 polish pass if picking proves clunky in daily use.
struct ReceiptCaptureView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var form = TransactionFormData()
    @State private var rawLines: [String] = []
    @State private var detectedItems: [ReceiptCandidates.LineItem] = []
    @State private var phase: Phase = .picking
    @State private var ocrError: String?

    // Batch scanning: pick several receipts at once and review them one by
    // one. The queue holds the not-yet-processed picker items (loaded
    // lazily, one image in memory at a time).
    @State private var itemQueue: [PhotosPickerItem] = []
    @State private var batchTotal = 0
    @State private var batchIndex = 0

    /// How many receipts one session may queue. Bounded so a slip of the
    /// finger in the photo grid can't enqueue an entire camera roll.
    private static let batchLimit = 10

    enum Phase { case picking, processing, reviewing }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .picking:
                    picker
                case .processing:
                    ProgressView("Reading receipt…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.backgroundGradient.ignoresSafeArea())
                case .reviewing:
                    reviewForm
                }
            }
            .navigationTitle(batchTotal > 1 ? "Receipt \(batchIndex) of \(batchTotal)" : "Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // Batch only: drop the current receipt without saving and
                // move on to the next one.
                if phase == .reviewing && batchTotal > 1 {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Skip") { advanceOrDismiss() }
                    }
                }
            }
        }
    }

    private var picker: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.accentMint)
            Text("Pick a photo of the receipt")
                .font(.headline)
            if let ocrError {
                Text(ocrError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            // Camera first — the quick path when the receipt is in hand.
            // The frame goes straight to OCR in memory; nothing is saved
            // to the photo library.
            Button {
                showCamera = true
            } label: {
                Label("Take photo", systemImage: "camera.fill")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppTheme.accentMint, in: Capsule())
                    .foregroundStyle(.black)
            }
            PhotosPicker(selection: $pickedItems, maxSelectionCount: Self.batchLimit, matching: .images) {
                Label("Choose from library (up to \(Self.batchLimit))", systemImage: "photo.on.rectangle")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                if let image {
                    batchTotal = 1
                    batchIndex = 1
                    runOCR(on: image)
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            itemQueue = newItems
            batchTotal = newItems.count
            batchIndex = 0
            pickedItems = []
            processNextInQueue()
        }
    }

    /// Pops the next queued receipt into OCR, or ends the session when the
    /// batch is exhausted.
    private func processNextInQueue() {
        guard !itemQueue.isEmpty else {
            dismiss()
            return
        }
        batchIndex += 1
        runOCR(on: itemQueue.removeFirst())
    }

    /// After a save or a skip: continue the batch or close the sheet.
    private func advanceOrDismiss() {
        if itemQueue.isEmpty {
            dismiss()
        } else {
            phase = .processing
            processNextInQueue()
        }
    }

    private var reviewForm: some View {
        VStack(spacing: 0) {
            TransactionFormView(
                form: $form,
                accounts: viewModel.accounts,
                categories: viewModel.categories,
                saveLabel: "Confirm & save"
            ) {
                if viewModel.save(form: form, source: .receiptOCR) {
                    advanceOrDismiss()
                }
            }
            if !detectedItems.isEmpty {
                DisclosureGroup("Items detected (\(detectedItems.count)) — saved for price history") {
                    ForEach(detectedItems, id: \.name) { item in
                        HStack {
                            Text(item.name).font(.caption)
                            Spacer()
                            Text("\(item.price)").font(.caption.monospacedDigit())
                        }
                    }
                }
                .padding(.horizontal)
                .background(AppTheme.backgroundGradientEnd)
            }
            // The raw OCR text, so a wrong guess can be diagnosed at a
            // glance instead of re-photographing.
            DisclosureGroup("What the scanner read (\(rawLines.count) lines)") {
                ScrollView {
                    Text(rawLines.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
            .padding()
            .background(AppTheme.backgroundGradientEnd)
        }
    }

    private func runOCR(on item: PhotosPickerItem) {
        phase = .processing
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try process(uiImage)
            } catch {
                // In a batch, one unreadable photo shouldn't sink the rest:
                // note the failure and move on to the next receipt.
                ocrError = batchTotal > 1
                    ? "Could not read photo \(batchIndex) of \(batchTotal): \(error.localizedDescription)"
                    : "Could not read that photo: \(error.localizedDescription)"
                if itemQueue.isEmpty {
                    phase = .picking
                } else {
                    processNextInQueue()
                }
            }
        }
    }

    private func runOCR(on uiImage: UIImage) {
        phase = .processing
        Task {
            do {
                try process(uiImage)
            } catch {
                ocrError = "Could not read that photo: \(error.localizedDescription)"
                phase = .picking
            }
        }
    }

    private func process(_ uiImage: UIImage) throws {
        guard let cgImage = uiImage.cgImage else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Forwarding the photo's orientation is load-bearing: camera
        // photos store pixels unrotated, and Vision's geometry (which the
        // merchant/total heuristics depend on) comes back sideways
        // without it.
        let candidates = try ReceiptOCRService().extractCandidates(
            from: cgImage,
            orientation: CGImagePropertyOrientation(uiImage.imageOrientation),
            // The user's merchant table doubles as a brand dictionary:
            // a receipt row matching a known merchant wins the merchant
            // guess outright (logo-image receipts print the brand only in
            // small legal text).
            knownMerchantKeywords: CategoryMatcher.keywordTable.map(\.keyword)
        )
        form = viewModel.makeForm(fromReceipt: candidates)
        rawLines = candidates.rawLines
        viewModel.pendingReceiptItems = candidates.lineItems
        detectedItems = candidates.lineItems
        phase = .reviewing
    }
}
