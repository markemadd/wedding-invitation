import SwiftUI
import AVFoundation
import Speech
import Capture
import UI

// MARK: - VoiceCaptureView (blueprint Phase 2.4)
// Hold-free flow: tap record → speak ("قهوة خمسين جنيه") → tap stop →
// on-device transcription → regex first-pass parse → pre-filled form →
// confirm. Same mandatory review as OCR.
struct VoiceCaptureView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var recorder = VoiceRecorder()
    @State private var phase: Phase = .idle
    @State private var transcript = ""
    @State private var form = TransactionFormData()
    @State private var voiceError: String?
    /// Persisted preference: SFSpeechRecognizer is single-locale, so
    /// Arabic/English is a toggle (WhisperKit would enable true mixed
    /// speech if Apple's recognizer proves insufficient in daily use).
    @AppStorage("voiceCaptureLanguage") private var languageRaw = VoiceCaptureService.Language.arabic.rawValue

    private var language: VoiceCaptureService.Language {
        VoiceCaptureService.Language(rawValue: languageRaw) ?? .arabic
    }

    enum Phase { case idle, recording, transcribing, reviewing }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle, .recording:
                    recordingUI
                case .transcribing:
                    ProgressView("Transcribing…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.backgroundGradient.ignoresSafeArea())
                case .reviewing:
                    reviewForm
                }
            }
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.cancel()
                        dismiss()
                    }
                }
            }
        }
    }

    private var recordingUI: some View {
        VStack(spacing: 24) {
            Picker("Language", selection: $languageRaw) {
                Text("عربي").tag(VoiceCaptureService.Language.arabic.rawValue)
                Text("English").tag(VoiceCaptureService.Language.english.rawValue)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            .disabled(phase == .recording)

            Image(systemName: phase == .recording ? "waveform" : "mic.fill")
                .font(.system(size: 56))
                .foregroundStyle(phase == .recording ? .red : AppTheme.accentMint)
                .symbolEffect(.pulse, isActive: phase == .recording)
            Text(phase == .recording ? "Listening… tap to stop" : "Tap and say the amount and merchant")
                .font(.headline)
                .multilineTextAlignment(.center)
            if let voiceError {
                Text(voiceError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button {
                phase == .recording ? stopAndTranscribe() : startRecording()
            } label: {
                Label(phase == .recording ? "Stop" : "Record", systemImage: phase == .recording ? "stop.fill" : "record.circle")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(phase == .recording ? Color.red : AppTheme.accentMint, in: Capsule())
                    .foregroundStyle(.black)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
    }

    private var reviewForm: some View {
        VStack(spacing: 0) {
            TransactionFormView(
                form: $form,
                accounts: viewModel.accounts,
                categories: viewModel.categories,
                saveLabel: "Confirm & save"
            ) {
                if viewModel.save(form: form, source: .voice) {
                    dismiss()
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Heard:")
                    .font(.caption.bold())
                Text(transcript)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppTheme.backgroundGradientEnd)
        }
    }

    private func startRecording() {
        voiceError = nil
        Task {
            do {
                try await recorder.start()
                phase = .recording
            } catch {
                voiceError = error.localizedDescription
            }
        }
    }

    private func stopAndTranscribe() {
        phase = .transcribing
        Task {
            do {
                let audioURL = try recorder.stop()
                // Speech-recognition permission is requested lazily, right
                // before first use — never at app launch.
                let granted = await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { status in
                        continuation.resume(returning: status == .authorized)
                    }
                }
                guard granted else {
                    throw VoiceError.recognizerUnavailable
                }
                transcript = try await VoiceCaptureService(language: language).transcribe(audioURL: audioURL)
                let parsed = VoiceDraftParser().parse(transcript)
                form = viewModel.makeForm(fromVoice: parsed)
                phase = .reviewing
            } catch {
                voiceError = "Could not transcribe: \(error.localizedDescription)"
                phase = .idle
            }
        }
    }
}

// MARK: - VoiceRecorder
// Minimal AVAudioRecorder wrapper: records a temp .m4a for the speech
// recognizer. Audio never leaves the device (recognition is forced
// on-device) and the temp file is deleted after use.
final class VoiceRecorder {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func start() async throws {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            throw VoiceRecorderError.microphoneDenied
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-capture-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.record()
        self.recorder = recorder
        self.fileURL = url
    }

    func stop() throws -> URL {
        guard let recorder, let fileURL else {
            throw VoiceRecorderError.notRecording
        }
        recorder.stop()
        self.recorder = nil
        return fileURL
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}

enum VoiceRecorderError: Error, LocalizedError {
    case microphoneDenied
    case notRecording

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Microphone access was denied — enable it in Settings to use voice capture."
        case .notRecording: return "No recording in progress."
        }
    }
}
