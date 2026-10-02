import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var showingAPIKey = false
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            APISettingsView(showingAPIKey: $showingAPIKey)
                .tabItem {
                    Label("API", systemImage: "key")
                }
            
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    
    var body: some View {
        Form {
            Section {
                Picker("Model", selection: $settingsManager.selectedModel) {
                    ForEach(SettingsManager.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                
                HStack {
                    Text("Temperature: \(settingsManager.temperature, specifier: "%.1f")")
                    Slider(value: $settingsManager.temperature, in: 0...2, step: 0.1)
                }
                
                Toggle("Stream responses", isOn: $settingsManager.streamResponses)
            } header: {
                Text("Chat Settings")
                    .font(.headline)
            }
            
            Section {
                Button("Reset to Defaults") {
                    settingsManager.resetToDefaults()
                }
            }
        }
        .padding()
    }
}

struct APISettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Binding var showingAPIKey: Bool
    @State private var tempAPIKey = ""
    
    var body: some View {
        Form {
            Section {
                HStack {
                    if showingAPIKey {
                        TextField("API Key", text: $tempAPIKey)
                            .onAppear {
                                tempAPIKey = settingsManager.apiKey
                            }
                            .onChange(of: tempAPIKey) { _, newValue in
                                settingsManager.apiKey = newValue
                            }
                    } else {
                        SecureField("API Key", text: $tempAPIKey)
                            .onAppear {
                                tempAPIKey = settingsManager.apiKey
                            }
                            .onChange(of: tempAPIKey) { _, newValue in
                                settingsManager.apiKey = newValue
                            }
                    }
                    
                    Button(action: {
                        showingAPIKey.toggle()
                    }) {
                        Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }
                
                Text("Get your API key from [console.x.ai](https://console.x.ai)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if settingsManager.isAPIKeySet {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("API key is set")
                            .font(.caption)
                    }
                }
            } header: {
                Text("xAI API Configuration")
                    .font(.headline)
            }
            
            Section {
                Text("During the beta period, you get $25 of free API credits per month.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject var settingsManager: SettingsManager = .shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Existing font / scheme
                GroupBox("Text & Theme") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Font Size: \(Int(settingsManager.fontSize))")
                            Slider(value: $settingsManager.fontSize, in: 10...20, step: 1)
                        }
                        Picker("Color Scheme", selection: $settingsManager.colorScheme) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                    }
                    .padding(4)
                }

                // Liquid glass chrome (Pand0ra-mirrored)
                GroupBox("Window Chrome") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Liquid glass chrome", isOn: Binding(
                            get: { settingsManager.glassAppearance.enabled },
                            set: { settingsManager.glassAppearance.enabled = $0 }
                        ))
                        .toggleStyle(.switch)

                        Text("Frosted see-through titlebar and toolbar. Grok web content stays opaque; only surrounding chrome is glass.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        glassPreview
                            .frame(height: 88)
                            .opacity(settingsManager.glassAppearance.enabled ? 1 : 0.55)

                        Group {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("See-through")
                                    Spacer()
                                    Text("\(Int(settingsManager.glassAppearance.seeThrough * 100))%")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .font(.subheadline)
                                Slider(
                                    value: Binding(
                                        get: { settingsManager.glassAppearance.seeThrough },
                                        set: { settingsManager.glassAppearance.seeThrough = $0 }
                                    ),
                                    in: 0...1
                                )
                                Text("Higher = more desktop visible. Low = solid matte near-black.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Material thickness")
                                    Spacer()
                                    Text(settingsManager.glassAppearance.thicknessLabel)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                                Slider(
                                    value: Binding(
                                        get: { settingsManager.glassAppearance.thickness },
                                        set: { settingsManager.glassAppearance.thickness = $0 }
                                    ),
                                    in: 0...1
                                )
                                Text("Ultra Thin → Ultra Thick blur.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Vibrancy / highlight")
                                    Spacer()
                                    Text("\(Int(settingsManager.glassAppearance.vibrancy * 100))%")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .font(.subheadline)
                                Slider(
                                    value: Binding(
                                        get: { settingsManager.glassAppearance.vibrancy },
                                        set: { settingsManager.glassAppearance.vibrancy = $0 }
                                    ),
                                    in: 0...1
                                )
                                Text("Edge highlight and shadow strength.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .disabled(!settingsManager.glassAppearance.enabled)
                        .opacity(settingsManager.glassAppearance.enabled ? 1 : 0.45)

                        HStack {
                            Button("Reset Look") { settingsManager.resetGlassAppearance() }
                                .buttonStyle(.bordered)
                            Spacer()
                        }
                    }
                    .padding(4)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var glassPreview: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.45),
                    Color.purple.opacity(0.35),
                    Color.cyan.opacity(0.30)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.clear)
                    .frame(width: 120, height: 56)
                    .background {
                        GlassChromeBackground(cornerRadius: 12, showShadow: true)
                    }
                    .overlay {
                        Text("Glass card")
                            .font(.caption.weight(.semibold))
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Live preview")
                        .font(.subheadline.weight(.semibold))
                    Text(settingsManager.glassAppearance.enabled
                         ? "\(settingsManager.glassAppearance.thicknessLabel) · \(Int(settingsManager.glassAppearance.seeThrough * 100))% clear"
                         : "Solid chrome")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }
}