import AppKit
import SwiftUI

/// Controls for every configuration key. Changes are written straight into
/// the config file, so the window and the file never disagree; editing the
/// file by hand updates these controls the same way.
struct SettingsView: View {
    @ObservedObject private var store = ConfigurationStore.shared
    @State private var isNamingPreset = false
    @State private var presetName = ""

    private let families = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    private func binding<Value>(_ keyPath: WritableKeyPath<Configuration, Value>) -> Binding<Value> {
        Binding(
            get: { store.current[keyPath: keyPath] },
            set: { value in
                var configuration = store.current
                configuration[keyPath: keyPath] = value
                store.write(configuration)
            }
        )
    }

    /// The preset whose values match the live configuration, or "None".
    /// Choosing a preset writes its values through to the config file.
    private var presetSelection: Binding<String> {
        Binding(
            get: { store.matchingPreset ?? "" },
            set: { name in
                if !name.isEmpty { store.applyPreset(named: name) }
            }
        )
    }

    /// A colour well bound to one hex override; nil shows the theme's colour.
    private func colorRow(_ title: String, _ keyPath: WritableKeyPath<Configuration, String?>, themeValue: KeyPath<Palette, String>) -> some View {
        let current = store.current[keyPath: keyPath] ?? store.current.theme.palette[keyPath: themeValue]
        let binding = Binding<Color>(
            get: { Color(nsColor: Appearance.color(hex: current)) },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                var configuration = store.current
                configuration[keyPath: keyPath] = HexColor.string(
                    red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent
                )
                store.write(configuration)
            }
        )
        return HStack {
            ColorPicker(title, selection: binding, supportsOpacity: false)
            Text(current)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
    }

    var body: some View {
        Form {
            Section("Presets") {
                Picker("Preset", selection: presetSelection) {
                    Text("None").tag("")
                    ForEach(store.presets, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Button("Save Current as Preset…") {
                        presetName = store.matchingPreset ?? ""
                        isNamingPreset = true
                    }
                    Spacer()
                    Button("Delete Preset", role: .destructive) {
                        if let name = store.matchingPreset { store.deletePreset(named: name) }
                    }
                    .disabled(store.matchingPreset == nil)
                }
            }

            Section("Theme") {
                Picker("Theme", selection: binding(\.theme)) {
                    ForEach(Theme.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                colorRow("Canvas", \.canvas, themeValue: \.canvas)
                colorRow("Ink", \.ink, themeValue: \.ink)
                colorRow("Canvas (dark)", \.canvasDark, themeValue: \.canvasDark)
                colorRow("Ink (dark)", \.inkDark, themeValue: \.inkDark)
                HStack {
                    Spacer()
                    Button("Use Theme Colours") {
                        var configuration = store.current
                        configuration.canvas = nil
                        configuration.ink = nil
                        configuration.canvasDark = nil
                        configuration.inkDark = nil
                        store.write(configuration)
                    }
                    .disabled([store.current.canvas, store.current.ink, store.current.canvasDark, store.current.inkDark].allSatisfy { $0 == nil })
                }
            }

            Section("Type") {
                Picker("Typeface", selection: binding(\.fontFamily)) {
                    if !families.contains(store.current.fontFamily) {
                        Text(store.current.fontFamily).tag(store.current.fontFamily)
                    }
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                numberRow("Size", binding(\.fontSize), in: Configuration.fontSizeRange, unit: "pt")
                numberRow("Line height", binding(\.lineHeight), in: Configuration.lineHeightRange, unit: "×")
                numberRow("Paragraph spacing", binding(\.paragraphSpacing), in: Configuration.paragraphSpacingRange, unit: "pt")
                numberRow("Measure", binding(\.measure), in: Configuration.measureRange, unit: "pt")
                numberRow("Letter spacing", binding(\.letterSpacing), in: Configuration.letterSpacingRange, unit: "pt")
                Picker("Heading weight", selection: binding(\.headingWeight)) {
                    ForEach(Configuration.HeadingWeight.allCases, id: \.self) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
            }


            Section {
                HStack {
                    Button("Reset to Defaults") { store.write(Configuration()) }
                    Spacer()
                    Button("Open Config File") { NSWorkspace.shared.open(store.fileURL) }
                }
                Text(store.fileURL.path(percentEncoded: false))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .background(SettingsWindowConfigurator())
        .alert("Save Preset", isPresented: $isNamingPreset) {
            TextField("Name", text: $presetName)
            Button("Save") { store.savePreset(named: presetName) }
                .disabled(!ConfigurationStore.isValidPresetName(presetName))
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current settings under this name. Saving with an existing name replaces that preset.")
        }
    }

    private func numberRow(
        _ title: String,
        _ value: Binding<Double>,
        in range: ClosedRange<Double>,
        unit: String
    ) -> some View {
        HStack {
            Slider(value: value, in: range) { Text(title) }
            TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
            Text(unit).frame(width: 18, alignment: .leading)
        }
    }
}

/// Lets the Settings window appear on top of a full-screen document instead
/// of switching to the desktop space.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> HostView { HostView(frame: .zero) }
    func updateNSView(_ view: HostView, context: Context) { view.configureWindow() }

    final class HostView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        func configureWindow() {
            window?.collectionBehavior.insert([.fullScreenAuxiliary, .moveToActiveSpace])
        }
    }
}
