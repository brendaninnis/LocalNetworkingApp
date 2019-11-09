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

    static let MESSAGE_TAG = 1
    static let NAME_TAG = 2
    
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var textField: UITextField!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var textFieldBottom: NSLayoutConstraint!
    
    var names = [
        "Belgarion",
        "Ce'Nedra",
        "Belgarath",
        "Polgara",
        "Durnik",
        "Silk",
        "Velvet",
        "Poledra",
        "Beldaran",
        "Beldin",
        "Geran",
        "Mandorallen",
        "Hettar",
        "Adara",
        "Barak"
    ]
    var myName = ""
    var socketNames: [GCDAsyncSocket: String] = [:]
    
    var netService: NetService?
    var socket: GCDAsyncSocket?
    let socketQueue = DispatchQueue.init(label: "HostSocketQueue")
    var connectedSockets: [GCDAsyncSocket] = []
    var netServiceBrowser: NetServiceBrowser?
    var serverAddresses: [Data]?
    
    var host = false
    var connected = false
    var joined = false
    
    var cannonicalThread: [Message] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Add listeners for keyboard events
        NotificationCenter.default.addObserver(self, selector:#selector(self.keyboardWillShow), name:UIResponder.keyboardDidShowNotification, object: nil)
        NotificationCenter.default.addObserver(self,selector: #selector(self.keyboardWillHide), name:UIResponder.keyboardDidHideNotification, object: nil)
        
        // Add join button
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Join", style: .plain, target: self, action: #selector(HostViewController.join))
    }
    
    func getName() -> String {
        return names.remove(at: Int(arc4random_uniform(UInt32(names.count))))
    }
    
    func putName(_ name: String) {
        names.append(name)
    }
    
    @objc func join() {
        self.navigationItem.rightBarButtonItem?.title = joined ? "Join" : "Leave"
        
        if joined {
            if host {
                stopHosting()
            } else {
                stopNetServiceBrowser()
                socket?.disconnect()
                socket = nil
                netService = nil
                serverAddresses = nil
            }
        } else {
            
            // Display connecting message
            var primaryColor = UIColor.darkText
            if #available(iOS 13.0, *) {
                primaryColor = UIColor.label
            }
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = NSTextAlignment.center
            let attributes = [
                NSAttributedString.Key.font: UIFont.systemFont(ofSize: 14.0),
                NSAttributedString.Key.foregroundColor: primaryColor,
                NSAttributedString.Key.paragraphStyle: paragraphStyle
            ]
            textView.attributedText = NSAttributedString(string: "Connecting...", attributes: attributes)
            
            // Browse for an existing service
            startNetServiceBrowser()
            
            // After 5 seconds, if no service has been found, start one
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if !self.connected {
                    self.stopNetServiceBrowser()
                    self.startHosting()
                }
            }
        }
        
        joined = !joined
    }
    
    func startNetServiceBrowser() {
        netServiceBrowser = NetServiceBrowser()
        netServiceBrowser?.delegate = self
        netServiceBrowser?.searchForServices(ofType: "_LocalNetworkingApp._tcp.", inDomain: "local.")
    }
    
    func stopNetServiceBrowser() {
        netServiceBrowser?.stop()
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
    
    func startHosting() {
        // Host mode on
        host = true
        
        // Get a name for the host
        myName = getName()
        
        // Reset text view
        textView.text = ""
        textView.attributedText = NSAttributedString(string: "")
        
        // Add a system message
        let message = Message(sender: Message.SERVER_MSG_SENDER, message: "\(myName) has started the chat", timestamp: Date())
        addMessage(message, toTextView: textView)
        
        // Initialize cannonical thread
        cannonicalThread = [message]
        
        // Create the listen socket and publish a net service
        socket = GCDAsyncSocket(delegate: self, delegateQueue: socketQueue)
        do {
            try socket?.accept(onPort: 0)
            let port = socket!.localPort
            
            netService = NetService(domain: "local.", type: "_LocalNetworkingApp._tcp.", name: "Host Device", port: Int32(port))
            netService?.delegate = self
            netService?.publish()
        } catch let error {
            print("ERROR: \(error)")
        }
        
        // Enable chat
        textField.isEnabled = true
        sendButton.isEnabled = true
    }
    
    func stopHosting() {
        // Stop listening
        socket?.disconnect()
        
        netService?.stop()
        netService = nil
        
        // Remove the clients
        for socket in connectedSockets {
            socket.disconnect()
        }
        
        // Remove my name
        putName(myName)
        myName = ""
        
        // Disable chat
        textField.isEnabled = false
        sendButton.isEnabled = false
        
        // Reset
        cannonicalThread = []
        textView.text = ""
        textView.attributedText = NSAttributedString(string: "")
        socket = nil
        
        // Host mode off
        host = false
    }
    
    func addMessage(_ message: Message, toTextView textView: UITextView, fromSelf: Bool = false) {
        let attributedString = NSMutableAttributedString(attributedString: textView.attributedText)
        var appending: NSMutableAttributedString
        var primaryColor = UIColor.darkText
        var secondaryColor = UIColor.darkGray
        if #available(iOS 13.0, *) {
            primaryColor = UIColor.label
            secondaryColor = UIColor.secondaryLabel
        }
        if message.sender == Message.SERVER_MSG_SENDER {
            // print server message
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = NSTextAlignment.center
            let attributes = [
                NSAttributedString.Key.font: UIFont.systemFont(ofSize: 13.0),
                NSAttributedString.Key.foregroundColor: secondaryColor,
                NSAttributedString.Key.paragraphStyle: paragraphStyle
            ]
            appending = NSMutableAttributedString(string: message.message + "\n\n", attributes: attributes)
        } else {
            // print message
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = fromSelf ? NSTextAlignment.right : NSTextAlignment.left
            var attributes = [
                NSAttributedString.Key.font: UIFont.systemFont(ofSize: 13.0),
                NSAttributedString.Key.foregroundColor: secondaryColor,
                NSAttributedString.Key.paragraphStyle: paragraphStyle
            ]
            appending = NSMutableAttributedString(string: message.sender + "\n", attributes: attributes)
            attributes[NSAttributedString.Key.font] = UIFont.systemFont(ofSize: 18.0)
            attributes[NSAttributedString.Key.foregroundColor] = primaryColor
            appending.append(NSMutableAttributedString(string: message.message + "\n\n", attributes: attributes))
        }
        attributedString.append(appending)
        textView.attributedText = attributedString
        
        // Scroll to the bottom of the text view
        if textView.attributedText.length > 0 {
            let location = textView.attributedText.length - 1
            let bottom = NSMakeRange(location, 1)
            textView.scrollRangeToVisible(bottom)
        }
    }
    

    @objc func keyboardWillShow(notification: Notification) {
        guard let userInfo = notification.userInfo,
            let frame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
                return
        }
        textFieldBottom.constant = frame.height + 16
    }

    @objc func keyboardWillHide(notification: Notification) {
        textFieldBottom.constant = 16
    }
    
    @IBAction func sendButtonTapped(_ sender: Any) {
        guard let text = textField.text,
            text != "",
            connected || host else {
            return
        }
        
        textView.resignFirstResponder()
        
        let message = Message(sender: myName, message: text, timestamp: Date())
        var messageData: Data
        do {
            messageData = try message.toJsonData()
        } catch let error {
            print("ERROR: Couldn't serialize message \(error)")
            return
        }
        messageData.append(GCDAsyncSocket.crlfData())
        
        // Add the message to the text view
        addMessage(message, toTextView: textView, fromSelf: true)
        
        // Send the message over the network
        if host {
            cannonicalThread.append(message)
            
            for client in connectedSockets {
                client.write(messageData, withTimeout: -1, tag: HostViewController.MESSAGE_TAG)
            }
        } else {
            socket?.write(messageData, withTimeout: -1, tag: HostViewController.MESSAGE_TAG)
        }
        
        textField.text = ""
    }
    
}

extension HostViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        sendButtonTapped(textField)
        return true
    }
}

extension HostViewController: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        print("ERROR: \(errorDict)")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        if netService == nil {
            netService = service
            netService?.delegate = self
            netService?.resolve(withTimeout: 5)
        }
    }
    
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        print("NetServiceBrowser did stop search")
    }
}

extension HostViewController: NetServiceDelegate {
    
    // Client
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("NetService did not resolve: \(errorDict)")
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        if serverAddresses == nil {
            serverAddresses = sender.addresses
        }
        if socket == nil {
            socket = GCDAsyncSocket(delegate: self, delegateQueue: socketQueue)
            connectToNextAddress()
        }
    }
    
    // Host
    func netServiceDidPublish(_ sender: NetService) {
        print("Bonjour Service Published: domain(\(sender.domain)) type(\(sender.type)) name(\(sender.name)) port(\(sender.port))")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("Failed to publish Bonjour Service domain(\(sender.domain)) type(\(sender.type)) name(\(sender.name))\n\(errorDict)")
    }
}

extension HostViewController: GCDAsyncSocketDelegate {
    func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        print("Socket did connect to host \(host) on port \(port)")
        connected = true
    
        DispatchQueue.main.async {
            // Reset chat
            self.textView.text = ""
            self.textView.attributedText = NSAttributedString(string: "")
            
            // Enable chat
            self.textField.isEnabled = true
            self.sendButton.isEnabled = true
        }
        
        // Connected to host, wait for a name
        socket?.readData(to: GCDAsyncSocket.crlfData(), withTimeout: -1, tag: HostViewController.NAME_TAG)
        print("Waiting for name \(socket!)")
    }
    
    func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        connectedSockets.append(newSocket)
        
        // Give the new client a name
        let name = getName()
        socketNames[newSocket] = name
        
        // Send the client their name
        guard var nameData = name.data(using: .utf8) else {
            print("ERROR: Couldn't encode name data")
            return
        }
        nameData.append(GCDAsyncSocket.crlfData())
        newSocket.write(nameData, withTimeout: -1, tag: HostViewController.NAME_TAG)
        
        // Send the client the cannonical thread
        for message in cannonicalThread {
            do {
                var messageData = try message.toJsonData()
                messageData.append(GCDAsyncSocket.crlfData())
                newSocket.write(messageData, withTimeout: -1, tag: HostViewController.MESSAGE_TAG)
            } catch let error {
                print("ERROR: \(error) - Couldn't serialize message \(message)")
            }
        }
        
        // Send a system message alerting that a client has joined
        let message = Message(sender: Message.SERVER_MSG_SENDER, message: "\(name) has joined", timestamp: Date())
        self.cannonicalThread.append(message)

        do {
            var messageData = try message.toJsonData()
            messageData.append(GCDAsyncSocket.crlfData())
            for client in connectedSockets {
                client.write(messageData, withTimeout: -1, tag: HostViewController.MESSAGE_TAG)
            }
        } catch let error {
            print("ERROR: \(error) - Couldn't serialize message \(message)")
        }
        
        DispatchQueue.main.async {
            self.addMessage(message, toTextView: self.textView)
        }
        
        // Wait for a message
        newSocket.readData(to: GCDAsyncSocket.crlfData(), withTimeout: -1, tag: HostViewController.MESSAGE_TAG)
    }
    
    func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        print("Socket did read data with tag \(tag)")

        switch tag {
        case HostViewController.MESSAGE_TAG:
            // Incoming message
            let messageData = data.dropLast(2)
            let message: Message
            do {
                message = try Message(jsonData: messageData)
            } catch let error {
                print("ERROR: Couldnt create Message from data \(error.localizedDescription)")
                return
            }
            
            DispatchQueue.main.async {
                self.addMessage(message, toTextView: self.textView)
            }
            
            if host {
                // Update the cannonical thread
                cannonicalThread.append(message)
                
                // Forward the message to clients
                for client in connectedSockets {
                    if client == sock {
                        // Don't send the message back to the client who sent it
                        continue
                    }
                    client.write(data, withTimeout: -1, tag: HostViewController.MESSAGE_TAG)
                }
            }
            break
        case HostViewController.NAME_TAG:
            // Received name from the server
            guard !host else {
                print("ERROR: Why is the host getting sent a name?")
                return
            }
            let stringData = data.dropLast(2)
            if let name = String(data: stringData, encoding: .utf8) {
                myName = name
            } else {
                print("ERROR: Couldn't initialize name from data")
            }
            break
        default:
            break
        }
        
        // Read the next message
        sock.readData(to: GCDAsyncSocket.crlfData(), withTimeout: -1, tag: HostViewController.MESSAGE_TAG)
    }
    
    func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        print("Socket did disconnect \(err?.localizedDescription ?? "")")
        if host {
            if let index = connectedSockets.firstIndex(of: sock) {
                connectedSockets.remove(at: index)
                
                // Remove the name
                if let name = socketNames[sock] {
                    putName(name)
                    socketNames[sock] = nil

                    // Send a system message alerting that a client has left
                    let message = Message(sender: Message.SERVER_MSG_SENDER, message: "\(name) has left", timestamp: Date())
                    self.cannonicalThread.append(message)

                    do {
                        var messageData = try message.toJsonData()
                        messageData.append(GCDAsyncSocket.crlfData())
                        for client in connectedSockets {
                            client.write(messageData, withTimeout: -1, tag: HostViewController.MESSAGE_TAG)
                        }
                    } catch let error {
                        print("ERROR: \(error) - Couldn't serialize message \(message)")
                    }
                    
                    DispatchQueue.main.async {
                        self.addMessage(message, toTextView: self.textView)
                    }
                }
            }
        } else {
            // Reset
            connected = false
            joined = false
            socket = nil
            netService = nil
            serverAddresses = nil
            
            // Disable chat
            DispatchQueue.main.async {
                self.textField.isEnabled = false
                self.sendButton.isEnabled = false
            }
        }
    }
}
