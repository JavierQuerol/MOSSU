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
    func reachability(_ reachability: Reachability, didJoinNetwork ssid: String)
}

class Reachability {
    weak var delegate: ReachabilityDelegate?
    let internetMonitor = NWPathMonitor()
    let internetQueue = DispatchQueue(label: "InternetMonitor")
    private var isCurrentlyReachable = false
    private var currentSSID = ""

    func startInternetTracking() {
        guard internetMonitor.pathUpdateHandler == nil else { return }
        internetMonitor.pathUpdateHandler = { [weak self] update in
            self?.handlePathUpdate(isReachable: update.status == .satisfied,
                                   ssid: Office.SSID.current().rawValue)
        }
        internetMonitor.start(queue: internetQueue)
    }

    /// Se llama en `internetQueue` con cada cambio de ruta.
    func handlePathUpdate(isReachable: Bool, ssid: String) {
        let previousSSID = currentSSID
        currentSSID = ssid
        if isCurrentlyReachable != isReachable {
            isCurrentlyReachable = isReachable
            DispatchQueue.main.async {
                self.delegate?.reachability(self, didUpdateInternetStatus: isReachable)
            }
        } else if isReachable, !ssid.isEmpty, ssid != previousSSID {
            // Cambiar de Wi-Fi no siempre pasa por "sin internet": con cable puesto, si el
            // salto es rápido o si ocurre durante el reposo, la ruta sigue satisfecha y sin
            // este aviso no se volvería a mirar dónde estás al llegar a la oficina.
            DispatchQueue.main.async {
                self.delegate?.reachability(self, didJoinNetwork: ssid)
            }
        }
    }
}
