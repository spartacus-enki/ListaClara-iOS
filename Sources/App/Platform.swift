import Foundation
import Security
import UserNotifications
import AVFoundation
import UIKit
import LocalAuthentication
import CryptoKit

struct Session: Codable {
    var base: URL
    var auth: JSON
    var identity: String { auth["serverId"].string + "/" + auth["userId"].string }
    var api: API { API(base: base, token: auth["token"].string) }
}
enum Vault {
    static let service = "mx.listaclara.ios.session"
    static func read() throws -> Session? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "current",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CoreError.message("No se pudo leer el llavero.") }
        return try JSONDecoder().decode(Session.self, from: data)
    }
    static func write(_ session: Session?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "current"]
        guard let session else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw CoreError.message("No se pudo cerrar la sesión local.") }; return
        }
        let data = try JSONEncoder().encode(session)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CoreError.message("No se pudo guardar la sesión.") }
        } else if status != errSecSuccess { throw CoreError.message("No se pudo actualizar la sesión.") }
    }
}
struct DiskStore {
    var url: URL
    init(identity: String) throws {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ListaClara", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        url = root.appendingPathComponent(key + ".json")
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var folder = root; try folder.setResourceValues(values)
    }
    func load() throws -> Ledger {
        guard FileManager.default.fileExists(atPath: url.path) else { return Ledger() }
        return try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: url))
    }
    func save(_ ledger: Ledger) throws {
        try JSONEncoder().encode(ledger).write(to: url, options: [.atomic, .completeFileProtection])
    }
}
@MainActor final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    let center = UNUserNotificationCenter.current()
    let speech = AVSpeechSynthesizer()
    var onForegroundReminder: ((String) -> Void)?
    var onOpenReminder: ((String) -> Void)?
    private var generation = 0
    override init() { super.init(); center.delegate = self }
    func authorize() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
    func reconcile(_ ledger: Ledger) async throws {
        generation += 1; let currentGeneration = generation
        let settings = await center.notificationSettings()
        guard currentGeneration == generation else { return }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        center.removeAllPendingNotificationRequests()
        for reminder in reminderPlan(ledger) {
            guard currentGeneration == generation else { return }
            let content = UNMutableNotificationContent()
            content.title = "Lista Clara"; content.body = "Tienes un recordatorio pendiente."
            content.sound = .default; content.userInfo = ["record": reminder.id]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.at.timeIntervalSinceNow), repeats: false)
            try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }
    func clear() { generation += 1; center.removeAllPendingNotificationRequests(); center.removeAllDeliveredNotifications(); speech.stopSpeaking(at: .immediate) }
    func speak(_ text: String) {
        guard UIApplication.shared.applicationState == .active else { return }
        speech.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text); utterance.voice = AVSpeechSynthesisVoice(language: "es-MX")
        speech.speak(utterance)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
        let key = notification.request.content.userInfo["record"] as? String ?? ""
        Task { @MainActor in self.onForegroundReminder?(key) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        let key = response.notification.request.content.userInfo["record"] as? String ?? ""
        Task { @MainActor in self.onOpenReminder?(key) }
        completionHandler()
    }

}
