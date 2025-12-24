import SwiftUI

struct SessionContextSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var speakers: [SpeakerInfo]
    @Binding var topicContext: String
    @Binding var preferredLanguage: String
    let onSave: () -> Void
    let isSaving: Bool

    private let languageOptions: [(label: String, code: String)] = [
        ("Device language", ""),
        ("English", "en"),
        ("Spanish", "es"),
        ("French", "fr"),
        ("German", "de"),
        ("Portuguese", "pt"),
        ("Japanese", "ja"),
        ("Korean", "ko"),
        ("Chinese", "zh")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient().ignoresSafeArea()
                Form {
                    Section(header: Text("Speakers")) {
                        Stepper("Number of speakers: \(speakers.count)", value: Binding(
                            get: { speakers.count },
                            set: { newValue in
                                if newValue > speakers.count {
                                    speakers.append(SpeakerInfo(name: "", role: nil))
                                } else if newValue < speakers.count {
                                    speakers.removeLast(speakers.count - newValue)
                                }
                            }
                        ), in: 0...12)

                        ForEach(speakers.indices, id: \.self) { index in
                            let binding = Binding(
                                get: { speakers[index] },
                                set: { speakers[index] = $0 }
                            )
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                TextField("Name", text: binding.name)
                                TextField("Role / Title", text: Binding(
                                    get: { binding.wrappedValue.role ?? "" },
                                    set: { binding.wrappedValue = SpeakerInfo(name: binding.wrappedValue.name, role: $0.isEmpty ? nil : $0) }
                                ))
                            }
                        }
                        .onDelete { indexSet in
                            speakers.remove(atOffsets: indexSet)
                        }

                        Button("Add speaker") {
                            speakers.append(SpeakerInfo(name: "", role: nil))
                        }
                    }

                    Section(header: Text("Session context")) {
                        TextField("Topic or context", text: $topicContext, axis: .vertical)
                    }

                    Section(header: Text("Summary language")) {
                        Picker("Language", selection: $preferredLanguage) {
                            ForEach(languageOptions, id: \.code) { option in
                                Text(option.label).tag(option.code)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Improve Summary")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppColors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Regenerate") {
                        onSave()
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}
