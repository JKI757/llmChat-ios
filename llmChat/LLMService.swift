import Foundation
import CoreData

class LLMService: NSObject, URLSessionDataDelegate {
    private var onUpdate: ((String, Bool) -> Void)?
    private var currentTask: URLSessionDataTask?
    private var useChatEndpoint: Bool
    
    init(useChatEndpoint: Bool) {
        self.useChatEndpoint = useChatEndpoint
        super.init()
    }

    static func sendStreamingMessage(
        message: String,
        prompt: String,
        model: String,
        apiToken: String,
        endpoint: String,
        preferredLanguage: String,
        useChatEndpoint: Bool,
        onUpdate: @escaping (String, Bool) -> Void
    ) -> LLMService {
        let service = LLMService(useChatEndpoint: useChatEndpoint)
        service.onUpdate = onUpdate
        service.startStreaming(message: message, prompt: prompt, model: model, apiToken: apiToken, endpoint: endpoint, preferredLanguage: preferredLanguage)
        return service
    }
    
    func cancelStreaming() {
        currentTask?.cancel()
    }
    
    private func startStreaming(
        message: String,
        prompt: String,
        model: String,
        apiToken: String,
        endpoint: String,
        preferredLanguage: String
    ) {
        let endpointPath = useChatEndpoint ? "/v1/chat/completions" : "/v1/completions"
        
        // Ensure endpoint has a valid scheme
        var baseEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !baseEndpoint.hasPrefix("http://") && !baseEndpoint.hasPrefix("https://") {
            baseEndpoint = "https://" + baseEndpoint
        }
        // Remove trailing slash if present
        baseEndpoint = baseEndpoint.hasSuffix("/") ? String(baseEndpoint.dropLast()) : baseEndpoint
        
        guard let url = URL(string: baseEndpoint + endpointPath) else {
            DispatchQueue.main.async {
                self.onUpdate?("Error: Invalid API endpoint: \(baseEndpoint + endpointPath)", true)
            }
            return
        }
        
        // guard !apiToken.isEmpty else {
        //     DispatchQueue.main.async {
        //         self.onUpdate?("Error: Missing API token", true)
        //     }
        //     return
        // }
        
        let systemPrompt = preferredLanguage == "English" ? "You are a helpful assistant." :
        "You are a helpful assistant. Respond in \(preferredLanguage) unless the user specifies otherwise."
        
        // Prepare request body based on endpoint type
        let json: [String: Any]
        if useChatEndpoint {
            json = [
                "model": model,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": message]
                ],
                "stream": true
            ]
        } else {
            json = [
                "model": model,
                "prompt": prompt,
                "stream": true
            ]
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json) else {
            DispatchQueue.main.async {
                self.onUpdate?("Failed to encode JSON", true)
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        currentTask = session.dataTask(with: request)
        currentTask?.resume()
    }
    
    // URLSessionDataDelegate method to capture streamed data
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let chunkString = String(data: data, encoding: .utf8) {
            DispatchQueue.main.async {
                self.onUpdate?(chunkString, false)
            }
        }
    }
    
    // URLSessionTaskDelegate method to signal completion or error
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.onUpdate?("Error: \(error.localizedDescription)", true)
            }
        } else {
            DispatchQueue.main.async {
                // Signal completion with an empty string (you may modify this as needed)
                self.onUpdate?("", true)
            }
        }
    }
}
