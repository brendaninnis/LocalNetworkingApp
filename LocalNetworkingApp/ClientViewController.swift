//
//  ClientViewController.swift
//  LocalNetworkingApp
//
//  Created by Brendan Innis on 2019-11-01.
//  Copyright © 2019 Brendan Innis. All rights reserved.
//

import UIKit
import CocoaAsyncSocket

class ClientViewController: UIViewController {

    var connected = false
    var netServiceBrowser: NetServiceBrowser!
    var serverAddresses: [Data]?
    var serverService: NetService?
    var socket: GCDAsyncSocket?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        netServiceBrowser = NetServiceBrowser()
        netServiceBrowser.delegate = self
        netServiceBrowser.searchForServices(ofType: "_LocalNetworkingApp._tcp.", inDomain: "local.")
    }

    func connectToNextAddress() {
        var done = false
        while (!done && serverAddresses?.count ?? 0 > 0) {
            if let addr = serverAddresses?.remove(at: 0) {
                do {
                    try socket?.connect(toAddress: addr)
                    done = true
                } catch let error {
                    print("ERROR: \(error)")
                }
            }
        }
        
        if !done {
            print("Unable to connect to any resolved address")
        }
    }
}

extension ClientViewController: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        print("ERROR: \(errorDict)")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        if serverService == nil {
            serverService = service
            serverService?.delegate = self
            serverService?.resolve(withTimeout: 5)
        }
    }
    
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        print("NetServiceBrowser did stop search")
    }
}

extension ClientViewController: NetServiceDelegate {
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("NetService did not resolve: \(errorDict)")
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        if serverAddresses == nil {
            serverAddresses = sender.addresses
        }
        if socket == nil {
            socket = GCDAsyncSocket(delegate: self, delegateQueue: DispatchQueue.main)
            connectToNextAddress()
        }
    }
}

extension ClientViewController: GCDAsyncSocketDelegate {
    func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        print("Socket did connect to host \(host) on port \(port)")
        connected = true
    }
    
    func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        print("Socket did disconnect \(err?.localizedDescription ?? "")")
        if !connected {
            connectToNextAddress()
        }
    }
}
