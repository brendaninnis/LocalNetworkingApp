//
//  ViewController.swift
//  LocalNetworkingApp
//
//  Created by Brendan Innis on 2019-11-01.
//  Copyright © 2019 Brendan Innis. All rights reserved.
//

import UIKit
import CocoaAsyncSocket

class ViewController: UIViewController {

    static let MESSAGE_TAG = 1
    static let NAME_TAG = 2
    
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var textField: UITextField!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var textFieldBottom: NSLayoutConstraint!
    
    let namesQueue = DispatchQueue(label: "SocketNamesQueue", attributes: .concurrent)
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
    
    let messagesArrayQueue = DispatchQueue(label: "CannonicalThreadQueue", attributes: .concurrent)
    var cannonicalThread: [Message] = []
    
    var netService: NetService?
    var socket: GCDAsyncSocket?
    let socketQueue = DispatchQueue(label: "HostSocketQueue")
    let clientArrayQueue = DispatchQueue(label: "ConnectedSocketsQueue", attributes: .concurrent)
    var connectedSockets: [GCDAsyncSocket] = []
    var netServiceBrowser: NetServiceBrowser?
    var serverAddresses: [Data]?
    
    var host = false
    var connected = false
    var joined = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Add listeners for keyboard events
        NotificationCenter.default.addObserver(self, selector:#selector(self.keyboardWillShow), name:UIResponder.keyboardDidShowNotification, object: nil)
        NotificationCenter.default.addObserver(self,selector: #selector(self.keyboardWillHide), name:UIResponder.keyboardDidHideNotification, object: nil)
        
        // Add join button
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Join", style: .plain, target: self, action: #selector(ViewController.join))
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
                netServiceBrowser?.stop()
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
            
            // After 3 seconds, if no service has been found, start one
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if !self.connected {
                    self.netServiceBrowser?.stop()
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
        // Create the listen socket
        socket = GCDAsyncSocket(delegate: self, delegateQueue: socketQueue)
        do {
            try socket?.accept(onPort: 0)
        } catch let error {
            print("ERROR: \(error)")
            return
        }

        let port = socket!.localPort
        
        // Publish a NetService
        netService = NetService(domain: "local.", type: "_LocalNetworkingApp._tcp.", name: "BelgariadChat", port: Int32(port))
        netService?.delegate = self
        netService?.publish()
        
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
        clientArrayQueue.async {
            for socket in self.connectedSockets {
                socket.disconnect()
            }
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
            messagesArrayQueue.async(flags: .barrier) {
                self.cannonicalThread.append(message)
            }
            
            clientArrayQueue.async {
                for client in self.connectedSockets {
                    client.write(messageData, withTimeout: -1, tag: ViewController.MESSAGE_TAG)
                }
            }
        } else {
            socket?.write(messageData, withTimeout: -1, tag: ViewController.MESSAGE_TAG)
        }
        
        textField.text = ""
    }
    
}

extension ViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        sendButtonTapped(textField)
        return true
    }
}

extension ViewController: NetServiceBrowserDelegate {
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

extension ViewController: NetServiceDelegate {
    
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

extension ViewController: GCDAsyncSocketDelegate {
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
        socket?.readData(to: GCDAsyncSocket.crlfData(), withTimeout: -1, tag: ViewController.NAME_TAG)
        print("Waiting for name \(socket!)")
    }
    
    func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        clientArrayQueue.async(flags: .barrier) {
            self.connectedSockets.append(newSocket)
        }
        
        // Give the new client a name
        var name = "Someone"
        namesQueue.sync(flags: .barrier) {
            name = getName()
            self.socketNames[newSocket] = name
        }
        
        // Send the client their name
        guard var nameData = name.data(using: .utf8) else {
            print("ERROR: Couldn't encode name data")
            return
        }
        nameData.append(GCDAsyncSocket.crlfData())
        newSocket.write(nameData, withTimeout: -1, tag: ViewController.NAME_TAG)
        
        // Send the client the cannonical thread
        messagesArrayQueue.async {
            for message in self.cannonicalThread {
                do {
                    var messageData = try message.toJsonData()
                    messageData.append(GCDAsyncSocket.crlfData())
                    newSocket.write(messageData, withTimeout: -1, tag: ViewController.MESSAGE_TAG)
                } catch let error {
                    print("ERROR: \(error) - Couldn't serialize message \(message)")
                }
            }
        }
        
        // Send a system message alerting that a client has joined
        let message = Message(sender: Message.SERVER_MSG_SENDER, message: "\(name) has joined", timestamp: Date())
        messagesArrayQueue.async(flags: .barrier) {
            self.cannonicalThread.append(message)
        }

        do {
            var messageData = try message.toJsonData()
            messageData.append(GCDAsyncSocket.crlfData())
            clientArrayQueue.async {
                for client in self.connectedSockets {
                    client.write(messageData, withTimeout: -1, tag: ViewController.MESSAGE_TAG)
                }
            }
        } catch let error {
            print("ERROR: \(error) - Couldn't serialize message \(message)")
        }
        
        DispatchQueue.main.async {
            self.addMessage(message, toTextView: self.textView)
        }
        
        // Wait for a message
        newSocket.readData(to: GCDAsyncSocket.crlfData(), withTimeout: -1, tag: ViewController.MESSAGE_TAG)
    }
    
    func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        print("Socket did read data with tag \(tag)")
        
        if let string = String(data: data, encoding: .utf8) {
            print(string)
        }

        switch tag {
        case ViewController.MESSAGE_TAG:
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
                messagesArrayQueue.async {
                    self.cannonicalThread.append(message)
                }
                
                // Forward the message to clients
                clientArrayQueue.async {
                    for client in self.connectedSockets {
                        if client == sock {
                            // Don't send the message back to the client who sent it
                            continue
                        }
                        client.write(data, withTimeout: -1, tag: ViewController.MESSAGE_TAG)
                    }
                }
            }
            break
        case ViewController.NAME_TAG:
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
        sock.readData(to: GCDAsyncSocket.crlfData(), withTimeout: -1, tag: ViewController.MESSAGE_TAG)
    }
    
    func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        print("Socket did disconnect \(err?.localizedDescription ?? "")")
        if host {
            clientArrayQueue.async(flags: .barrier) {
                if let index = self.connectedSockets.firstIndex(of: sock) {
                    self.connectedSockets.remove(at: index)
                }
            }
            
            // Remove the name
            var name = "Someone"
            namesQueue.sync(flags: .barrier) {
                guard let innerName = socketNames[sock] else {
                    return
                }
                name = innerName
                putName(name)
                socketNames[sock] = nil
            }

            let message = Message(sender: Message.SERVER_MSG_SENDER, message: "\(name) has left", timestamp: Date())
            // Send a system message alerting that a client has left
            messagesArrayQueue.async(flags: .barrier) {
                self.cannonicalThread.append(message)
            }

            do {
                var messageData = try message.toJsonData()
                messageData.append(GCDAsyncSocket.crlfData())
                clientArrayQueue.async {
                    for client in self.connectedSockets {
                        client.write(messageData, withTimeout: -1, tag: ViewController.MESSAGE_TAG)
                    }
                }
            } catch let error {
                print("ERROR: \(error) - Couldn't serialize message \(message)")
            }
            
            DispatchQueue.main.async {
                self.addMessage(message, toTextView: self.textView)
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
