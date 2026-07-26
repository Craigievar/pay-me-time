import FamilyControls

@MainActor
enum ScreenTimeAuthorizationService {
    static var status: AuthorizationStatus {
        AuthorizationCenter.shared.authorizationStatus
    }

    static func request() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }
}
