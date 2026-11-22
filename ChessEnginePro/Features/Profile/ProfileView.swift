//
//  ProfileView.swift
//  CHESS ENGINE PRO
//
//  Local profile, statistics, engine configuration and settings entry point.
//

import SwiftUI

struct ProfileView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var stats: TrainingStatsStore
    @EnvironmentObject private var analysis: AnalysisManager

    @State private var showSettings = false

    private var initials: String {
        let name = settings.settings.playerName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.map(String.init).joined().uppercased()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                profileHeader
                statsGrid
                engineCard
                menuCard
                chessComCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 26)
        }
        .background(Theme.background)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(environment)
                .environmentObject(settings)
                .environmentObject(analysis)
        }
    }

    // MARK: - Sections

    private var profileHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.accentMuted)
                    .frame(width: 62, height: 62)
                Text(initials)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(settings.settings.playerName.isEmpty ? "Spieler" : settings.settings.playerName)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(settings.settings.chessComHandle.isEmpty
                     ? "Lokales Profil"
                     : "Chess.com: \(settings.settings.chessComHandle)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                HStack(spacing: 6) {
                    Pill(text: analysis.usesStockfish ? "Stockfish" : "Swift-Engine",
                         color: analysis.usesStockfish ? Theme.accent : Theme.warning,
                         icon: "cpu")
                    if stats.stats.streak > 0 {
                        Pill(text: "\(stats.stats.streak) Tage Serie", color: Theme.warning, icon: "flame.fill")
                    }
                }
            }
            Spacer()
        }
        .premiumCard()
    }

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Statistik")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                StatTile(title: "Aufgaben gelöst", value: "\(stats.stats.puzzlesSolved)", icon: "checkmark.circle.fill")
                StatTile(title: "Versuche", value: "\(stats.stats.puzzlesAttempted)", icon: "repeat", tint: Theme.info)
                StatTile(title: "Partien", value: "\(stats.stats.gamesPlayed)", icon: "flag.fill", tint: Theme.warning)
                StatTile(title: "Analysen", value: "\(environment.store.count)", icon: "chart.bar.fill", tint: Color(hex: 0xC2A6F0))
            }
        }
    }

    private var engineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Engine-Konfiguration", subtitle: analysis.engineName)
            DividerLine()
            HStack(spacing: 8) {
                configCell("Tiefe", "\(settings.settings.depth)")
                configCell("MultiPV", "\(settings.settings.multiPV)")
                configCell("Threads", "\(settings.settings.effectiveThreads)")
                configCell("Hash", "\(settings.settings.hashMB)")
            }
            Text(StockfishBuild.isLinked
                 ? "Stockfish \(StockfishBuild.version) läuft eingebettet auf dem Gerät."
                 : "Stockfish ist in diesem Build nicht eingebunden – die eingebaute Engine übernimmt.")
                .font(.system(size: 10))
                .foregroundStyle(StockfishBuild.isLinked ? Theme.secondaryText : Theme.warning)
            Button {
                showSettings = true
            } label: {
                Label("Engine & Analyse konfigurieren", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
        }
        .premiumCard()
    }

    private func configCell(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.text)
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.field))
    }

    private var menuCard: some View {
        VStack(spacing: 0) {
            menuRow(icon: "gearshape.fill", title: "Einstellungen", subtitle: "Engine, Darstellung, Performance") {
                showSettings = true
            }
            DividerLine()
            menuRow(icon: "lock.shield.fill", title: "Datenschutz", subtitle: "Lokale Daten, Sitzungen") {
                showSettings = true
            }
            DividerLine()
            menuRow(icon: "info.circle.fill", title: "Über CHESS ENGINE PRO", subtitle: "Version & Lizenzen") {
                showSettings = true
            }
        }
        .padding(.horizontal, 14)
        .premiumCard(padding: 4, radius: 18)
    }

    private func menuRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    private var chessComCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Chess.com-Verbindung")
            Text("Sitzung und Anmeldung werden im Play-Tab über den offiziellen Chess.com-WebView verwaltet. Passwörter werden nie in der App gespeichert.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                environment.selectedTab = .chessCom
            } label: {
                Label("Zum Play-Tab", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
        }
        .premiumCard()
    }
}
