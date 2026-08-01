import SwiftUI

/// Profile — notifications, offline packs, travel defaults, and what the app is holding.
struct ProfileScreen: View {
    @Environment(AppState.self) private var app

    /// Measured off the disk rather than estimated: this is the one storage number on
    /// the screen that is a fact.
    @State private var photoBytes = 0

    private var photoStorageLine: String {
        guard photoBytes > 0 else { return "No park photographs stored yet" }
        let megabytes = Double(photoBytes) / 1024 / 1024
        let cap = PhotoStore.capBytes / 1024 / 1024
        return String(format: "%.0f MB of park photographs · %d MB ceiling", megabytes, cap)
    }

    private func measurePhotos() async {
        photoBytes = await PhotoStore.shared.bytesUsed
    }

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            ScreenHeader {
                Text("ParkHop \(AppVersion.short) · a field planner").kickerStyle()
                Text("Profile").font(WP.display(31)).padding(.top, 4)
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    identity

                    sectionLabel("Tell me when")
                    Grouped {
                        toggleRow("Permit windows drop",
                                  "Timed entry, lotteries, next-day releases",
                                  isOn: app.notifyPermits) {
                            app.notifyPermits.toggle()
                            app.show(app.notifyPermits ? "Notifications on" : "Notifications off")
                            app.persist()
                        }
                        Hairline()
                        toggleRow("Park alerts on my route",
                                  "Closures, fire, flash flood, road work",
                                  isOn: app.notifyAlerts) {
                            app.notifyAlerts.toggle()
                            app.persist()
                        }
                        Hairline()
                        toggleRow("Live Activity on drive legs",
                                  "Arrival time and next charge on the lock screen",
                                  isOn: app.notifyLive) {
                            app.notifyLive.toggle()
                            app.persist()
                        }
                    }

                    sectionLabel("Park packs for no signal")
                    Grouped {
                        ForEach(Array(app.library.orderedParks.enumerated()), id: \.element.code) { index, park in
                            packRow(park)
                            if index < app.library.orderedParks.count - 1 { Hairline() }
                        }
                        Hairline()
                        // The pack figure is the curated library's own; the photograph
                        // figure is measured off the disk, because that one is real.
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(app.packStorageMB) MB of park packs on this iPhone")
                                .font(WP.bodyItalic(11.5)).opacity(0.6)
                            HStack(spacing: 10) {
                                Text(photoStorageLine)
                                    .font(WP.bodyItalic(11.5)).opacity(0.6)
                                Spacer(minLength: 0)
                                if photoBytes > 0 {
                                    Button {
                                        Task {
                                            await PhotoStore.shared.clear()
                                            await measurePhotos()
                                            app.show("Photographs cleared")
                                        }
                                    } label: {
                                        Text("Clear")
                                            .font(WP.headingUI(12))
                                            .padding(.horizontal, 12)
                                            .frame(minHeight: 28)
                                            .glassControl(shadow: false)
                                    }
                                    .buttonStyle(PressStyle(scale: 0.95))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                    }

                    sectionLabel("Travel defaults")
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Vehicle").font(WP.body(12)).opacity(0.65)
                            SegmentedTrough(
                                options: [(false, "Gasoline"), (true, "Electric")],
                                selection: Binding(get: { app.vehicleIsElectric },
                                                   set: { app.vehicleIsElectric = $0; app.persist() })
                            )
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Units").font(WP.body(12)).opacity(0.65)
                            SegmentedTrough(
                                options: [(false, "Miles · °F"), (true, "Km · °C")],
                                selection: Binding(get: { app.unitsMetric },
                                                   set: { app.unitsMetric = $0; app.persist() })
                            )
                        }
                    }

                    sectionLabel("Data & offline")
                    Grouped {
                        HStack(spacing: 10) {
                            Circle().fill(WP.live).frame(width: 7, height: 7)
                            Text("Curated field library").font(WP.body(14))
                            Spacer(minLength: 0)
                            Text("NPS · Open-Meteo · Recreation.gov")
                                .font(WP.body(11.5)).opacity(0.55).lineLimit(1)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        Hairline()
                        HStack {
                            Text("Field journal").font(WP.body(14))
                            Spacer(minLength: 0)
                            Text("\(app.journalCount) photographs").font(WP.body(11.5)).opacity(0.55)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        Hairline()
                        HStack {
                            Text("Live sources").font(WP.body(14))
                            Spacer(minLength: 0)
                            Text("Re-wiring next pass").font(WP.body(11.5)).opacity(0.55)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 13)
                    }

                    Text("Every panel says where its rows came from. What you are reading now is the curated field library that ships with ParkHop — the live sources are being re-wired onto these screens, and until they are, nothing here claims to be today's measurement.")
                        .font(WP.bodyItalic(11.5)).opacity(0.55).lineSpacing(3)
                        .padding(.top, 22)

                    Text("Always confirm campsites, permits and closures with the park before you travel. ParkHop is a planner, not a promise.")
                        .font(WP.bodyItalic(11.5)).opacity(0.5).lineSpacing(3)
                        .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WP.gutter)
                .padding(.top, 18)
                .padding(.bottom, WP.tabBarClearance)
            }
            .scrollIndicators(.hidden)
        }
        .task { await measurePhotos() }
    }

    private var identity: some View {
        HStack(spacing: 13) {
            Text("MH")
                .font(WP.heading(21))
                .foregroundStyle(WP.accent800)
                .frame(width: 54, height: 54)
                .background(WP.accent100, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Miriam Halloran").font(WP.heading(20))
                Text("Trips synced by iCloud · 3 devices").font(WP.body(12)).opacity(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(WP.body(10)).tracking(1.4).opacity(0.5)
            .padding(.top, 22).padding(.bottom, 8)
    }

    private func toggleRow(_ title: String, _ subtitle: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(WP.body(14))
                    Text(subtitle).font(WP.body(11.5)).opacity(0.6).lineSpacing(1)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                WPSwitch(isOn: isOn)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.995))
    }

    private func packRow(_ park: CuratedPark) -> some View {
        let state = app.packState(park.code)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(park.name).font(WP.body(14))
                Text(park.pack).font(WP.body(11.5)).opacity(0.55)
            }
            Spacer(minLength: 0)
            Button {
                app.startPack(park.code)
            } label: {
                Text(state == .ready ? "On device"
                     : state == .busy ? "\(Int((app.packProgress[park.code] ?? 0) * 100))%"
                     : "Get")
                    .font(WP.headingUI(12.5))
                    .padding(.horizontal, 13)
                    .frame(minHeight: 32)
                    .glassControl(shadow: false)
            }
            .buttonStyle(PressStyle(scale: 0.95))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// The grouped-inset card iOS uses for settings, in the Classical palette.
struct Grouped<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(WP.neutral100, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(WP.divider, lineWidth: 1))
    }
}
