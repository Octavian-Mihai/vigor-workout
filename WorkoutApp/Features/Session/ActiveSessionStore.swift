import SwiftUI

@MainActor
final class ActiveSessionStore: ObservableObject {
    @Published var controller: SessionController?
    @Published var isPresented = false

    var isMinimized: Bool { controller != nil && !isPresented }

    func start(program: Program?, programDay: ProgramDay?) {
        if controller != nil {
            isPresented = true
            return
        }
        let rest = UserDefaults.standard.object(forKey: "defaultRestSeconds") as? Int ?? 90
        controller = SessionController(program: program, programDay: programDay, defaultRest: rest)
        isPresented = true
    }

    func start(from session: WorkoutSession) {
        if controller != nil {
            isPresented = true
            return
        }
        let rest = UserDefaults.standard.object(forKey: "defaultRestSeconds") as? Int ?? 90
        controller = SessionController(from: session, defaultRest: rest)
        isPresented = true
    }

    func minimize() {
        isPresented = false
    }

    func resume() {
        guard controller != nil else { return }
        isPresented = true
    }

    func finish() {
        controller?.stopTimer()
        RestTimerService.shared.resetRest()
        controller = nil
        isPresented = false
    }

    func discard() {
        controller?.stopTimer()
        RestTimerService.shared.resetRest()
        controller = nil
        isPresented = false
    }
}
