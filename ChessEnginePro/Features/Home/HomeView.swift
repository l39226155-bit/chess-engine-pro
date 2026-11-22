//
//  HomeView.swift
//  CHESS ENGINE PRO
//
//  Dashboard: Chess.com entry point, quick actions, recent analyses,
//  engine status and local statistics.
//

import SwiftUI

struct HomeView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var stats: TrainingStatsStore
    @EnvironmentObject private var analysis: AnalysisManager

    @State private var recent: [AnalysisRecord] = []
    @State private var showImporter = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                chessComCard
                quickActions
                engineCard
                statsRow
                recentSection
                privacyNote
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Theme.background)
        .onAppear { recent = environment.store.records(limit: 5) }
        .pgnImporter(isPresented: $showImporter) { game in
            environment.openInAnalysis(game: game)
        } onError: { message in
            environment.showToast(message)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("CHESS ENGINE PRO")
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .tracking(0.6)
                Text("Analyse · Training · Chess.com")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            EngineStatusBadge(name: analysis.engineName.isEmpty ? StockfishBuild.displayName : analysis.engineName,
                              isRunning: analysis.isAnalyzing,
                              depth: analysis.depth)
        }
    }

    private var chessComCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Chess.com")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("Melde dich mit deinem bestehenden Konto an und spiele direkt in der App.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "safari.fill")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.accent)
            }

            Button {
                environment.selectedTab = .chessCom
            } label: {
                Label("Chess.com öffnen", systemImage: "arrow.up.right.square.fill")
            }
            .buttonStyle(PrimaryButtonStyle())

            HStack(spacing: 8) {
                Pill(text: "WKWebView", icon: "lock.shield.fill")
                Pill(text: "Sitzung bleibt lokal", icon: "iphone")
                Spacer()
            }
        }
        .premiumCard()
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Schnellzugriff")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                QuickActionCard(icon: "square.grid.3x3.fill",
                                title: "Neue Analyse",
                                subtitle: "Brett & Engine",
                                tint: Theme.accent) {
                    analysis.reset()
                    environment.selectedTab = .stockfish
                }
                QuickActionCard(icon: "doc.badge.arrow.up",
                                title: "PGN importieren",
                                subtitle: "Partie auswerten",
                                tint: Theme.info) {
                    showImporter = true
                }
                QuickActionCard(icon: "graduationcap.fill",
                                title: "Training",
                                subtitle: "Taktik & Matts",
                                tint: Theme.warning) {
                    environment.selectedTab = .training
                }
                QuickActionCard(icon: "cpu.fill",
                                title: "Engine-Setup",
                                subtitle: "Tiefe & Threads",
                                tint: Color(hex: 0xC2A6F0)) {
                    environment.selectedTab = .settings
                }
            }
        }
    }

    private var engineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Engine", subtitle: analysis.engineName.isEmpty ? StockfishBuild.displayName : analysis.engineName)
                Spacer()
                Pill(text: analysis.isAnalyzing ? "Analysiert" : "Bereit",
                     color: analysis.isAnalyzing ? Theme.accent : Theme.secondaryText)
            }

            HStack(spacing: 10) {
                metric(title: "Tiefe", value: "\(analysis.depth)")
                metric(title: "MultiPV", value: "\(settings.settings.multiPV)")
                metric(title: "Threads", value: "\(settings.settings.effectiveThreads)")
                metric(title: "Hash", value: "\(settings.settings.hashMB) MB")
            }

            HStack(spacing: 10) {
                Button {
                    analysis.analyze()
                    environment.selectedTab = .stockfish
                } label: {
                    Label("Analyse öffnen", systemImage: "play.fill")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    analysis.flip()
                } label: {
                    Label("Brett drehen", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            if !StockfishBuild.isLinked {
                Text("Hinweis: Die Stockfish-Bibliothek ist in diesem Build nicht eingebunden – es läuft die eingebaute Swift-Engine. Der CI-Build bindet Stockfish automatisch ein.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .premiumCard()
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.text)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field))
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatTile(title: "Aufgaben gelöst", value: "\(stats.stats.puzzlesSolved)", icon: "checkmark.circle.fill")
            StatTile(title: "Analysen", value: "\(environment.store.count)", icon: "chart.bar.fill", tint: Theme.info)
            StatTile(title: "Serie", value: "\(stats.stats.streak) T", icon: "flame.fill", tint: Theme.warning)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Letzte Analysen",
                          subtitle: recent.isEmpty ? nil : "\(environment.store.count) gespeichert")
            if recent.isEmpty {
                EmptyStateView(icon: "clock.arrow.circlepath",
                               title: "Noch keine Analysen",
                               message: "Starte eine Analyse und speichere das Ergebnis – es erscheint hier.")
            } else {
                VStack(spacing: 8) {
                    ForEach(recent) { record in
                        Button {
                            open(record)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(Theme.accent.opacity(0.12)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.title)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(1)
                                    Text("\(record.summary) · \(record.formattedDate)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.secondaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            Text("Deine Chess.com-Zugangsdaten werden ausschließlich im WebView von Chess.com eingegeben und niemals von dieser App gelesen oder gespeichert. Die Engine arbeitet vollständig offline.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func open(_ record: AnalysisRecord) {
        if let pgn = record.pgn, let game = try? PGN.parseGame(pgn) {
            environment.openInAnalysis(game: game)
        } else {
            environment.openInAnalysis(fen: record.fen)
        }
    }
}

// MARK: - Quick action card

private struct QuickActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var tint: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.12)))
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .premiumCard(padding: 14, radius: 16)
        }
        .buttonStyle(.plain)
    }
}
