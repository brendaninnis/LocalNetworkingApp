//
//  Message.swift
//  LocalNetworkingApp
//
//  Created by Brendan Innis on 2019-11-01.
//  Copyright © 2019 Brendan Innis. All rights reserved.
//

import Foundation

struct Message {
    
    static let SERVER_MSG_SENDER = "SERVER_MSG_SENDER"
    static let SENDER_KEY = "SENDER_KEY"
    static let MESSAGE_KEY = "MESSAGE_KEY"
    static let TIMESTAMP_KEY = "TIMESTAMP_KEY"
    
    let sender: String
    let message: String
    let timestamp: Date
    
    init(sender: String, message: String, timestamp: Date) {
        self.sender = sender
        self.message = message
        self.timestamp = timestamp
    }
    
    init(jsonData: Data) throws {
        var sender = ""
        var message = ""
        var timestamp = Date()
        if let dict = try JSONSerialization.jsonObject(with: jsonData, options: .mutableLeaves) as? NSDictionary {
            sender = dict[Message.SENDER_KEY] as? String ?? ""
            message = dict[Message.MESSAGE_KEY] as? String ?? ""
            if let interval = dict[Message.TIMESTAMP_KEY] as? TimeInterval {
                timestamp = Date(timeIntervalSince1970: interval)
            }
        }
        self.sender = sender
        self.message = message
        self.timestamp = timestamp
    }
    
    init(dict: Dictionary<String, Any>) {
        self.sender = dict[Message.SENDER_KEY] as? String ?? ""
        self.message = dict[Message.MESSAGE_KEY] as? String ?? ""
        if let interval = dict[Message.TIMESTAMP_KEY] as? TimeInterval {
            self.timestamp = Date(timeIntervalSince1970: interval)
        } else {
            self.timestamp = Date()
        }
    }
    
    func toDict() -> Dictionary<String, Any> {
        var dict = Dictionary<String, Any>()
        dict[Message.SENDER_KEY] = self.sender
        dict[Message.MESSAGE_KEY] = self.message
        dict[Message.TIMESTAMP_KEY] = self.timestamp.timeIntervalSince1970
        return dict
    }
    
    func toJsonData() throws -> Data {
        return try JSONSerialization.data(withJSONObject: toDict(), options: .fragmentsAllowed)
    }
}

extension Array {
    static func messagesFromJsonData(_ jsonData: Data) throws -> [Message] {
        var messages: [Message] = []
        if let array = try JSONSerialization.jsonObject(with: jsonData, options: .mutableLeaves) as? NSArray {
            for case let dict as Dictionary<String, Any> in array {
                messages.append(Message(dict: dict))
            }
        }
        return messages
    }
    
    func messagesToJsonData() throws -> Data {
        var jsonArray: [Dictionary<String, Any>] = []
        for case let message as Message in self {
            jsonArray.append(message.toDict())
        }
        return try JSONSerialization.data(withJSONObject: jsonArray, options: .fragmentsAllowed)
    }
}
