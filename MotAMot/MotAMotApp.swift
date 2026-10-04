import SwiftUI

@main
struct MotAMotApp: App {
    @StateObject private var store = Store()
    @StateObject private var speech = Speech()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(speech)
                .preferredColorScheme(store.colorScheme)
                .tint(Palette.pen)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var speech: Speech
    @Environment(\.scenePhase) private var scenePhase

    private var sessionShowing: Binding<Bool> {
        Binding(
            get: { store.study != nil || store.quiz != nil || store.lastResult != nil },
            set: { shown in
                if !shown {
                    store.study = nil
                    store.quiz = nil
                    store.lastResult = nil
                }
            }
        )
    }

    var body: some View {
        TabView(selection: $store.tab) {
            LearnView()
                .tabItem { Label("Learn", systemImage: "square.stack.3d.up") }
                .tag(Tab.learn)
            ReadView()
                .tabItem { Label("Read", systemImage: "book") }
                .tag(Tab.read)
            WordsView()
                .tabItem { Label("Words", systemImage: "list.bullet") }
                .tag(Tab.words)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(Tab.settings)
        }
        .fullScreenCover(isPresented: sessionShowing) {
            SessionView()
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                ToastView(text: toast)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.toast)
        .onChange(of: store.toast) { _, message in
            guard let message = message else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if store.toast == message { store.toast = nil }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { speech.reloadVoices() }
            if phase == .background { store.persist() }
        }
    }
}

/// Study, test and result all live in one full-screen flow, so moving between
/// them doesn't flash the tab bar.
struct SessionView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        Group {
            if store.study != nil {
                StudyView()
            } else if store.quiz != nil {
                QuizView()
            } else if store.lastResult != nil {
                ResultView()
            } else {
                Color.clear
            }
        }
        .screenBackground()
    }
}
