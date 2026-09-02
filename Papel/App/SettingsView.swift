import AppKit
import SwiftUI

/// Controls for every configuration key. Changes are written straight into
/// the config file, so the window and the file never disagree; editing the
/// file by hand updates these controls the same way.
struct SettingsView: View {
    @ObservedObject private var store = ConfigurationStore.shared
    @State private var isNamingPreset = false
    @State private var isRenamingPreset = false
    @State private var presetName = ""
    @State private var isNamingTheme = false
    @State private var themeName = ""

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

    /// The active preset, or "None". Choosing a preset writes its values
    /// through to the config file; it stays selected while edited.
    private var presetSelection: Binding<String> {
        Binding(
            get: { store.activePreset ?? "" },
            set: { name in
                if !name.isEmpty { store.applyPreset(named: name) }
            }
        )
    }

    /// The configured theme name. A name no theme has (its file was
    /// removed) is listed so the picker still shows what the config says.
    private var themeSelection: Binding<String> {
        Binding(
            get: { store.current.theme },
            set: { name in
                var configuration = store.current
                configuration.theme = name
                store.write(configuration)
            }
        )
    }

    /// A colour well bound to one hex override; nil shows the theme's colour.
    private func colorRow(_ title: String, _ keyPath: WritableKeyPath<Configuration, String?>, themeValue: KeyPath<Palette, String>) -> some View {
        let current = store.current[keyPath: keyPath] ?? store.resolvedTheme.palette[keyPath: themeValue]
        func write(_ hex: String) {
            var configuration = store.current
            configuration[keyPath: keyPath] = hex
            store.write(configuration)
        }
        let binding = Binding<Color>(
            get: { Color(nsColor: Appearance.color(hex: current)) },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                write(HexColor.string(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent))
            }
        )
        return HStack {
            ColorPicker(title, selection: binding, supportsOpacity: false)
            HexField(value: current, commit: write)
        }
    }

    var body: some View {
        Form {
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

            Section("Presets") {
                Picker("Preset", selection: presetSelection) {
                    Text("None").tag("")
                    ForEach(store.presets, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Button("Save as New Preset…") {
                        presetName = ""
                        isNamingPreset = true
                    }
                    Spacer()
                    Button("Rename…") {
                        presetName = store.activePreset ?? ""
                        isRenamingPreset = true
                    }
                    .disabled(store.activePreset == nil)
                    Button("Delete", role: .destructive) {
                        if let name = store.activePreset { store.deletePreset(named: name) }
                    }
                    .disabled(store.activePreset == nil)
                }
            }

            Section("Theme") {
                Picker("Theme", selection: themeSelection) {
                    let builtIn = store.themes.filter(\.isBuiltIn)
                    let custom = store.themes.filter { !$0.isBuiltIn }
                    if store.theme(named: store.current.theme) == nil {
                        Text("\(store.current.theme) (missing)").tag(store.current.theme)
                    }
                    if custom.isEmpty {
                        ForEach(builtIn) { Text($0.title).tag($0.name) }
                    } else {
                        Section("Built-in") { ForEach(builtIn) { Text($0.title).tag($0.name) } }
                        Section("Custom") { ForEach(custom) { Text($0.title).tag($0.name) } }
                    }
                }
                colorRow("Canvas", \.canvas, themeValue: \.canvas)
                colorRow("Ink", \.ink, themeValue: \.ink)
                colorRow("Canvas (dark)", \.canvasDark, themeValue: \.canvasDark)
                colorRow("Ink (dark)", \.inkDark, themeValue: \.inkDark)
                HStack {
                    Button("Save as Theme…") {
                        themeName = ""
                        isNamingTheme = true
                    }
                    Spacer()
                    Button("Delete Theme", role: .destructive) { store.deleteTheme(named: store.current.theme) }
                        .disabled(store.resolvedTheme.isBuiltIn)
                    Button("Use Theme Colours") {
                        var configuration = store.current
                        configuration.colorOverrides = Palette.Overrides()
                        store.write(configuration)
                    }
                    .disabled(store.current.colorOverrides.isEmpty)
                }
                Text("Themes are files in \(store.themesDirectoryURL.path(percentEncoded: false)); a file named like a built-in replaces it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                numberRow("Letter spacing", binding(\.letterSpacing), in: Configuration.letterSpacingRange, unit: "pt")
                numberRow("Paragraph spacing", binding(\.paragraphSpacing), in: Configuration.paragraphSpacingRange, unit: "pt")
                numberRow("Measure", binding(\.measure), in: Configuration.measureRange, unit: "pt")
                Picker("Heading weight", selection: binding(\.headingWeight)) {
                    ForEach(Configuration.HeadingWeight.allCases, id: \.self) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
            }

            Section("Images") {
                numberRow("Corner radius", binding(\.imageCornerRadius), in: Configuration.imageCornerRadiusRange, unit: "pt")
            }


            Section("Window") {
                numberRow("Width", binding(\.windowWidth), in: Configuration.windowWidthRange, unit: "pt")
                numberRow("Height", binding(\.windowHeight), in: Configuration.windowHeightRange, unit: "pt")
                Text("Applies to new windows; each window keeps its own size afterwards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Text("Saves the current settings under this name and makes it the active preset. An existing name is replaced.")
        }
        .alert("Save Theme", isPresented: $isNamingTheme) {
            TextField("Name", text: $themeName)
            Button("Save") { store.saveTheme(named: themeName) }
                .disabled(!ConfigurationStore.isValidPresetName(themeName))
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the colours in use as a theme file under this name and selects it. An existing theme of that name is replaced.")
        }
        .alert("Rename Preset", isPresented: $isRenamingPreset) {
            TextField("Name", text: $presetName)
            Button("Rename") {
                if let name = store.activePreset { store.renamePreset(named: name, to: presetName) }
            }
            .disabled(!ConfigurationStore.isValidPresetName(presetName))
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Renames the active preset's file. A name already in use is refused.")
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

/// A hex colour field beside a colour well. Edits commit on Return or when
/// focus leaves; invalid text snaps back to the current value.
private struct HexField: View {
    let value: String
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Hex", text: $draft)
            .labelsHidden()
            .font(.system(.body, design: .monospaced))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 88)
            .focused($focused)
            .onAppear { draft = value }
            .onChange(of: value) { _, new in if !focused { draft = new } }
            .onChange(of: focused) { _, isFocused in if !isFocused { submit() } }
            .onSubmit(submit)
    }

    private func submit() {
        if let hex = HexColor.normalized(draft), hex != value {
            commit(hex)
        }
        draft = HexColor.normalized(draft) ?? value
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
