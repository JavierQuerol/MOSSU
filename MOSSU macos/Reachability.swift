//
//  Reachability.swift
//  MOSSU
//
//  Created by Javier Querol on 13/9/22.
//

import Foundation
import Network

protocol ReachabilityDelegate: AnyObject {
    func reachability(_ reachability: Reachability, didUpdateInternetStatus isAvailable: Bool)
}

class Reachability {
    weak var delegate: ReachabilityDelegate?
    let internetMonitor = NWPathMonitor()
    let internetQueue = DispatchQueue(label: "InternetMonitor")
    
    func startInternetTracking() {
        guard internetMonitor.pathUpdateHandler == nil else { return }
        internetMonitor.pathUpdateHandler = { [weak self] update in
            let isReachable = update.status == .satisfied
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.delegate?.reachability(self, didUpdateInternetStatus: isReachable)
            }
        }
        internetMonitor.start(queue: internetQueue)
    }
}
