import SwiftUI

/// The hidden options sheet, opened with a two-finger hold.
struct OptionsView: View {
    @AppStorage(GagSettings.Key.screen) private var screen: PrankScreen = .glass
    @AppStorage(GagSettings.Key.style) private var style: ShatterStyle = .random
    @AppStorage(GagSettings.Key.hits) private var hits = 3
    @AppStorage(GagSettings.Key.hinge) private var hinge = 40.0
    @AppStorage(GagSettings.Key.repair) private var repair: RepairStyle = .random
    @AppStorage(GagSettings.Key.autoRepair) private var autoRepair = true
    @AppStorage(GagSettings.Key.gotcha) private var gotcha = true
    @AppStorage(GagSettings.Key.sound) private var sound = true
    @AppStorage(GagSettings.Key.haptics) private var haptics = true
    @AppStorage(GagSettings.Key.count) private var count = 0
    @AppStorage(GagSettings.Key.crackPattern) private var crackPattern: CrackPattern = .random
    @AppStorage(GagSettings.Key.crackgate) private var crackgate = false

    let previews: [PrankScreen: UIImage]
    let previewAspect: CGFloat
    let onDone: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(PrankScreen.allCases) { option in
                            screenTile(option)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Screen")
                } footer: {
                    Text("Fake screens look like a real phone. Hand it over and let them tap.")
                }

                Section {
                    Toggle(isOn: $crackgate) {
                        Label("Crackgate Mode", systemImage: "rectangle.portrait.split.2x1")
                    }
                } header: {
                    Text("Crackgate 😬")
                } footer: {
                    Text("Recreates the iPhone Duo reports: a crunch as it unfolds, a crack straight down the crease, and a block of pixels stuck glowing white. Hand someone the folded phone and let them open it.")
                }

                Section {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(CrackPattern.allCases) { option in
                            tile(title: option.title, symbol: option.symbol, selected: crackPattern == option) { crackPattern = option }
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Crack Pattern")
                } footer: {
                    Text("Surprise Me picks a different pattern for every hit.")
                }
                .disabled(crackgate)

                Section {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(ShatterStyle.allCases) { option in
                            styleTile(option)
                        }
                    }
                    .padding(.vertical, 6)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Taps before it explodes")
                        Picker("Taps before it explodes", selection: $hits) {
                            Text("1").tag(1)
                            Text("2").tag(2)
                            Text("3").tag(3)
                            Text("5").tag(5)
                            Text("8").tag(8)
                            Text("Never").tag(0)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hinge sensitivity")
                        Picker("Hinge sensitivity", selection: $hinge) {
                            Text("Sturdy").tag(65.0)
                            Text("Normal").tag(40.0)
                            Text("Fragile").tag(20.0)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                } header: {
                    Text("Shatter")
                } footer: {
                    Text("“Never” leaves a cracked screen: the classic prank.")
                }
                .disabled(crackgate)

                Section("After it breaks") {
                    Picker("Repair animation", selection: $repair) {
                        ForEach(RepairStyle.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Repair automatically", isOn: $autoRepair)
                    Toggle("Reveal “Gotcha!” on fake screens", isOn: $gotcha)
                }

                Section("Feedback") {
                    Toggle("Sound", isOn: $sound)
                    Toggle("Haptics", isOn: $haptics)
                }

                Section {
                    LabeledContent("Panes shattered", value: "\(count)")
                    Button("Reset Counter", role: .destructive) { count = 0 }
                } footer: {
                    Text("Hold anywhere with two fingers to come back here. Shake the phone to smash it outright.")
                }
            }
            .navigationTitle("Shattter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    private func screenTile(_ option: PrankScreen) -> some View {
        let selected = screen == option
        return Button {
            screen = option
        } label: {
            VStack(spacing: 6) {
                Group {
                    if let image = previews[option] {
                        Image(uiImage: image).resizable()
                    } else {
                        Color.black
                    }
                }
                .aspectRatio(previewAspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1)
                }
                Text(option.title)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func styleTile(_ option: ShatterStyle) -> some View {
        tile(title: option.title, symbol: option.symbol, selected: style == option) { style = option }
    }

    private func tile(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(height: 26)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
