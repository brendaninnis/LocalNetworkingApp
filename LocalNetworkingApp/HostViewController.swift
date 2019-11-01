//
//  ViewController.swift
//  LocalNetworkingApp
//
//  Created by Brendan Innis on 2019-11-01.
//  Copyright © 2019 Brendan Innis. All rights reserved.
//

import UIKit
import CocoaAsyncSocket

class HostViewController: UIViewController {

    var netService: NetService!
    var socket: GCDAsyncSocket!
    var connectedSockets: [GCDAsyncSocket] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        socket = GCDAsyncSocket(delegate: self, delegateQueue: DispatchQueue.main)
        do {
            try socket.accept(onPort: 0)
            let port = socket.localPort
            
            netService = NetService(domain: "local.", type: "_LocalNetworkingApp._tcp.", name: "Host Device", port: Int32(port))
            netService.delegate = self
            netService.publish()
        } catch let error {
            print("ERROR: \(error)")
        }
    }
}

extension HostViewController: GCDAsyncSocketDelegate {
    func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        connectedSockets.append(newSocket)
    }
    
    func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        if let index = connectedSockets.firstIndex(of: sock) {
            connectedSockets.remove(at: index)
        }
    }
}

extension HostViewController: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        print("Bonjour Service Published: domain(\(sender.domain)) type(\(sender.type)) name(\(sender.name)) port(\(sender.port))")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("Failed to publish Bonjour Service domain(\(sender.domain)) type(\(sender.type)) name(\(sender.name))\n\(errorDict)")
    }
}
