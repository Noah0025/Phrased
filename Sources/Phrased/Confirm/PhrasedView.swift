import SwiftUI

// MARK: - PhrasedView

struct PhrasedView: View {
    @ObservedObject var inputVM: InputViewModel
    @ObservedObject var confirmVM: ConfirmViewModel

    // editorHeight lives in InputViewModel so PhrasedWindowController can observe it
    @State private var pulsing = false
    @State private var showCursor = true
    @FocusState private var feedbackFocused: Bool

    private var showResult: Bool {
        confirmVM.isStreaming || !confirmVM.streamedResult.isEmpty
    }
    private var isSubmitDisabled: Bool {
        inputVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !inputVM.isRecording && !inputVM.isTranscribing
    }
    private var acceptOutputMode: OutputMode {
        inputVM.settings.defaultOutputMode
    }
    private var acceptLabel: String {
        if acceptOutputMode == .inject {
            return String(localized: confirmVM.didCopy ? "confirm.button.inserted" : "confirm.button.insert")
        }
        return String(localized: confirmVM.didCopy ? "confirm.button.copied" : "confirm.button.copy")
    }

    var body: some View {
        VStack(spacing: 0) {
            if let appName = inputVM.contextAppName {
                HStack(spacing: PhrasedSpacing.xs) {
                    Image(systemName: "app.badge")
                        .font(.caption2).foregroundColor(.secondary.opacity(PhrasedOpacity.dimmed))
                    Text(appName)
                        .font(.caption2).foregroundColor(.secondary.opacity(PhrasedOpacity.muted))
                    Spacer()
                }
                .padding(.horizontal, PhrasedSpacing.md)
                .padding(.top, PhrasedSpacing.sm)
            }
            inputBar

            if showResult {
                Divider()
                resultArea
                if confirmVM.showFeedbackField {
                    Divider()
                    feedbackArea
                }
                Divider()
                actionBar
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: PhrasedRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: PhrasedRadius.lg)
                .strokeBorder(
                    inputVM.isRecording ? Color.red.opacity(PhrasedOpacity.dimmed) : Color.primary.opacity(PhrasedOpacity.lightFill),
                    lineWidth: 1
                )
        )
        .frame(width: 500)
        .animation(PhrasedAnimation.spring, value: showResult)
        .animation(PhrasedAnimation.spring, value: confirmVM.showFeedbackField)
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            if confirmVM.isStreaming { showCursor.toggle() } else { showCursor = false }
        }
        .onChange(of: inputVM.selectedTemplate) { newTemplate in
            guard showResult else { return }
            confirmVM.start(
                input: confirmVM.originalInput,
                template: newTemplate,
                context: confirmVM.currentContext
            )
        }
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 0) {
            micButton
                .padding(.leading, PhrasedSpacing.sm + 2)
                .padding(.bottom, PhrasedSpacing.sm + 1)

            inputArea
                .padding(.horizontal, PhrasedSpacing.sm)
                .padding(.vertical, PhrasedSpacing.sm + 2)

            if !showResult && !inputVM.isRecording && !inputVM.isTranscribing {
                compactTemplateMenu
                    .frame(height: 28)
                    .padding(.bottom, PhrasedSpacing.sm + 1)
            }

            Spacer().frame(width: PhrasedSpacing.md)

            submitButton
                .padding(.trailing, PhrasedSpacing.sm + 2)
                .padding(.bottom, PhrasedSpacing.sm + 1)
        }
    }

    // MARK: Mic button

    private var micButton: some View {
        Button {
            inputVM.toggleRecording()
        } label: {
            Image(systemName: "waveform")
                .font(PhrasedFont.bodyMedium)
                .foregroundColor(inputVM.isRecording ? .red : .secondary)
                .opacity(inputVM.isRecording && pulsing ? PhrasedOpacity.dimmed : 1.0)
                .animation(
                    inputVM.isRecording
                        ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                        : .default,
                    value: pulsing
                )
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(String(localized: inputVM.isRecording ? "confirm.help.stop_recording" : "confirm.help.start_recording"))
        .accessibilityLabel(String(localized: inputVM.isRecording ? "confirm.help.stop_recording" : "confirm.help.start_recording"))
        .onChange(of: inputVM.isRecording) { pulsing = $0 }
    }

    // MARK: Input area

    @ViewBuilder
    private var inputArea: some View {
        if let error = inputVM.transcribeError {
            HStack(spacing: PhrasedSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(PhrasedFont.ui)
                Text(error)
                    .font(PhrasedFont.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            }
        } else if inputVM.isRecording {
            Text(inputVM.inputText)
                .font(PhrasedFont.body)
                .foregroundColor(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        } else if inputVM.isTranscribing {
            HStack(alignment: .center, spacing: PhrasedSpacing.sm) {
                Text(inputVM.inputText)
                    .font(PhrasedFont.body)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                ProgressView().scaleEffect(0.65).frame(width: 14, height: 14)
            }
            .contentShape(Rectangle())
            .onTapGesture { inputVM.cancelRecording() }
        } else {
            AutoGrowingTextEditor(
                text: $inputVM.inputText,
                height: $inputVM.editorHeight,
                onFocus: { inputVM.cancelRecording() },
                onSubmit: { inputVM.submit() }
            )
            .frame(height: inputVM.editorHeight)
            .clipped()
        }
    }

    // MARK: Style picker

    private var stylePicker: some View {
        Picker("", selection: $inputVM.selectedTemplate) {
            ForEach(inputVM.allTemplates) { t in
                Text(t.name).tag(t)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 88)
        .labelsHidden()
    }

    private var compactTemplateMenu: some View {
        Menu {
            ForEach(inputVM.allTemplates) { t in
                Button(t.name) {
                    inputVM.selectedTemplate = t
                }
            }
        } label: {
            HStack(spacing: PhrasedSpacing.xs) {
                Text(inputVM.selectedTemplate.name)
                    .font(PhrasedFont.caption)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: Submit button

    private var submitButton: some View {
        Button { inputVM.submit() } label: {
            Image(systemName: "wand.and.stars")
                .font(PhrasedFont.bodyMedium)
                .foregroundColor(isSubmitDisabled ? .secondary : .accentColor)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(isSubmitDisabled)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel(String(localized: "shortcut.default.submit"))
    }

    // MARK: Result area

    private var resultArea: some View {
        VStack(alignment: .leading, spacing: PhrasedSpacing.sm) {
            HStack(alignment: .top, spacing: 0) {
                Group {
                    if confirmVM.streamedResult.isEmpty && confirmVM.isStreaming {
                        Text("confirm.generating")
                            .foregroundColor(.secondary)
                    } else {
                        Text(confirmVM.streamedResult)
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(PhrasedFont.body)
                .frame(maxWidth: .infinity, alignment: .leading)

                if confirmVM.isStreaming {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 18)
                        .opacity(showCursor ? 1 : 0)
                        .padding(.top, 2)
                }
            }

            if let error = confirmVM.streamError {
                Text(error)
                    .font(PhrasedFont.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(PhrasedSpacing.md + 2)
        .frame(maxWidth: .infinity, minHeight: 52)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(confirmVM.isStreaming ? String(localized: "confirm.generating") : String(localized: "accessibility.result"))
        .accessibilityValue(confirmVM.streamedResult)
    }

    // MARK: Feedback area

    private var feedbackArea: some View {
        HStack(spacing: PhrasedSpacing.sm) {
            TextField("confirm.feedback.placeholder", text: $confirmVM.feedbackText)
                .font(PhrasedFont.ui)
                .textFieldStyle(.roundedBorder)
                .focused($feedbackFocused)
            Button("confirm.button.generate") { confirmVM.regenerate() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(confirmVM.isStreaming)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, PhrasedSpacing.md)
        .padding(.vertical, PhrasedSpacing.sm)
        .onAppear { feedbackFocused = true }
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: PhrasedSpacing.sm) {
            Button {
                confirmVM.isLocked.toggle()
            } label: {
                Image(systemName: confirmVM.isLocked ? "pin.fill" : "pin")
                    .font(PhrasedFont.ui)
                    .foregroundColor(confirmVM.isLocked ? .accentColor : .secondary)
                    .rotationEffect(confirmVM.isLocked ? .degrees(-45) : .zero)
            }
            .buttonStyle(.plain)
            .help(String(localized: confirmVM.isLocked ? "confirm.help.locked" : "confirm.help.lock_window"))
            .accessibilityLabel(String(localized: confirmVM.isLocked ? "confirm.help.locked" : "confirm.help.lock_window"))

            Text("confirm.style")
                .font(PhrasedFont.ui)
                .foregroundColor(.secondary)

            stylePicker

            Spacer()

            Button { confirmVM.showFeedbackField.toggle() } label: {
                Image(systemName: "square.and.pencil")
                    .font(PhrasedFont.ui)
                    .foregroundColor(.secondary)
            }
            .disabled(confirmVM.isStreaming)
            .buttonStyle(.plain)
            .padding(.horizontal, PhrasedSpacing.sm)
            .padding(.vertical, PhrasedSpacing.xs + 1)
            .background(RoundedRectangle(cornerRadius: PhrasedRadius.sm).fill(Color.primary.opacity(PhrasedOpacity.subtleFill)))
            .help(String(localized: "confirm.help.feedback"))
            .accessibilityLabel(String(localized: "confirm.help.feedback"))

            Button { confirmVM.regenerate() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(PhrasedFont.ui)
                    .foregroundColor(.secondary)
            }
            .disabled(confirmVM.isStreaming)
            .buttonStyle(.plain)
            .padding(.horizontal, PhrasedSpacing.sm)
            .padding(.vertical, PhrasedSpacing.xs + 1)
            .background(RoundedRectangle(cornerRadius: PhrasedRadius.sm).fill(Color.primary.opacity(PhrasedOpacity.subtleFill)))
            .help(String(localized: "confirm.help.regenerate"))
            .accessibilityLabel(String(localized: "confirm.help.regenerate"))

            Button(acceptLabel) { confirmVM.accept(outputMode: acceptOutputMode) }
                .keyboardShortcut(.return)
                .disabled(confirmVM.isStreaming || confirmVM.streamedResult.isEmpty)
                .buttonStyle(.plain)
                .font(PhrasedFont.uiMedium)
                .foregroundColor(confirmVM.isStreaming || confirmVM.streamedResult.isEmpty ? .secondary : .white)
                .padding(.horizontal, PhrasedSpacing.md)
                .padding(.vertical, PhrasedSpacing.xs + 1)
                .background(
                    RoundedRectangle(cornerRadius: PhrasedRadius.sm)
                        .fill(confirmVM.isStreaming || confirmVM.streamedResult.isEmpty
                              ? Color.primary.opacity(PhrasedOpacity.lightFill)
                              : Color.accentColor)
                )
                .accessibilityLabel(acceptLabel)
        }
        .padding(.horizontal, PhrasedSpacing.md)
        .padding(.vertical, PhrasedSpacing.sm + 1)
    }
}
