//
//  Reachability.swift
//  MOSSU
//
//  Created by Javier Querol on 13/9/22.
//

import Foundation
import Network

class Reachability {
    let internetMonitor = NWPathMonitor()
    let internetQueue = DispatchQueue(label: "InternetMonitor")
    
    func startInternetTracking(completion: @escaping (Bool) -> ()) {
        guard internetMonitor.pathUpdateHandler == nil else { return }
        internetMonitor.pathUpdateHandler = { update in
            completion(update.status == .satisfied ? true : false)
        }
        internetMonitor.start(queue: internetQueue)
    }
}
