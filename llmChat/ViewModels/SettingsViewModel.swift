import Foundation
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var showingEndpoints = false
    @Published var showingAbout = false
    
    // App version information
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    // User preferences
    @AppStorage("userName") var userName: String = ""
    @AppStorage("appearance") var appearance: Int = 0
    @AppStorage("hapticsEnabled") var hapticsEnabled = true
    @AppStorage("analyticsEnabled") var analyticsEnabled = true
    
    var appearanceModes: [String] = ["System", "Light", "Dark"]
    
    // MARK: - Actions
    
    func openTwitter() {
        let username = "your_twitter_handle"
        let appURL = URL(string: "twitter://user?screen_name=\(username)")!
        let webURL = URL(string: "https://twitter.com/\(username)")!
        
        if UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else {
            UIApplication.shared.open(webURL)
        }
    }
    
    func openGitHub() {
        let url = URL(string: "https://github.com/yourusername/llmchat")!
        UIApplication.shared.open(url)
    }
    
    func sendFeedback() {
        let email = "support@yourapp.com"
        let subject = "LLM Chat Feedback"
        let body = """
        \n\n\n---
App Version: \(appVersion) (\(buildNumber))
Device: \(UIDevice.current.modelName)
iOS: \(UIDevice.current.systemVersion)
"""
        
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "mailto:\(email)?subject=\(encodedSubject)&body=\(encodedBody)"
        
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    func rateApp() {
        // Replace with your App Store ID
        let appID = "your_app_id"
        let url = "itms-apps://itunes.apple.com/app/id\(appID)?action=write-review"
        
        if let url = URL(string: url) {
            UIApplication.shared.open(url)
        }
    }
    
    func shareApp() {
        let text = "Check out LLM Chat - A beautiful client for LLM APIs"
        let url = URL(string: "https://apps.apple.com/app/id\(appVersion)")!
        
        let activityViewController = UIActivityViewController(
            activityItems: [text, url],
            applicationActivities: nil
        )
        
        // Present the share sheet
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityViewController, animated: true)
        }
    }
}

// MARK: - Device Info Extension

extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}
