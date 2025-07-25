//
//  Slack.swift
//  MOSSU
//
//  Created by Javier Querol on 9/9/22.
//

import Foundation

class Slack {
    static func getStatus(token: String, completion: @escaping (Result<(String, String), Error>) -> Void) {
        var request = URLRequest(url: URL(string: "https://slack.com/api/users.profile.get")!)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let urlSession = URLSession(configuration: .ephemeral)
        urlSession.dataTask(with: request) { data, response, error in
            guard let data = data else { return }
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let profile = json["profile"] as? [String: Any],
               let displayName = profile["display_name"] as? String,
               let statusEmoji = profile["status_emoji"] as? String {
                DispatchQueue.main.async { completion(.success((statusEmoji, displayName))) }
            } else {
                guard let error = error else { return }
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
    
    static func update(given office: Office, token: String, completion: @escaping (Error?) -> Void) {
        var request = URLRequest(url: URL(string: "https://slack.com/api/users.profile.set")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let params = [
            "profile": [
                "status_text": office.text,
                "status_emoji": office.emoji,
                "status_expiration": 0
            ]
        ]
        let paramsData = try? JSONSerialization.data(withJSONObject: params)
        request.httpBody = paramsData
        
        LogManager.shared.log("💭 Intentando actualizar a \"\(office.text)\"")
        
        let urlSession = URLSession(configuration: .ephemeral)
        urlSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                completion(error)
            }
        }.resume()
    }
}
