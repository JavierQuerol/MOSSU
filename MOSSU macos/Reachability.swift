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
    private var isCurrentlyReachable = false
    
    func startInternetTracking() {
        guard internetMonitor.pathUpdateHandler == nil else { return }
        internetMonitor.pathUpdateHandler = { [weak self] update in
            let isReachable = update.status == .satisfied
            guard let self = self else { return }
            if self.isCurrentlyReachable != isReachable {
                self.isCurrentlyReachable = isReachable
                DispatchQueue.main.async {
                    self.delegate?.reachability(self, didUpdateInternetStatus: isReachable)
                }
            }
        }
        internetMonitor.start(queue: internetQueue)
    }
    
    func stopInternetTracking() {
        internetMonitor.cancel()
    }
}
