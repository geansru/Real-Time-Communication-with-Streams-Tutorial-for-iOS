//
//  ChatRoom.swift
//  DogeChat
//
//  Created by Dmitriy Roytman on 21.07.17.
//  Copyright © 2017 Luke Parham. All rights reserved.
//

import UIKit

protocol ChatRoomDelegate: class {
    func receivedMessage(message: Message)
}

final class ChatRoom: NSObject {
    var inputStream: InputStream!
    var outputStream: OutputStream!
    var username = ""
    let maxReadLength = 4096
    weak var delegate: ChatRoomDelegate?
    
    func setupNetworkCommunication() {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, "127.0.0.1" as CFString, 80, &readStream, &writeStream)
        inputStream = readStream!.takeRetainedValue() as! InputStream
        outputStream = writeStream!.takeRetainedValue() as! OutputStream
        inputStream.delegate = self
        inputStream.schedule(in: .current, forMode: .commonModes)
        outputStream.schedule(in: .current, forMode: .commonModes)
        inputStream.open()
        outputStream.open()
    }
    
    func joinChat(username: String) {
        let data = user(username)
        self.username = username
        send(data)
    }
}

extension ChatRoom: StreamDelegate {
    enum Key: String {
        case iam = "iam", msg = "msg"
    }
    func convert(text: String) -> (_ key: Key ) -> Data {
        return { (key: Key)-> Data in
            return "\(key.rawValue):\(text)".data(using: .ascii)!
        }
    }
    func message(_ text: String) -> Data {
        return convert(text: text)(.msg)
    }
    func user(_ username: String) -> Data {
        return convert(text: username)(.iam)
    }
    func send(_ data: Data) {
        _ = data.withUnsafeBytes { [unowned self] in
            self.outputStream.write($0, maxLength: data.count)
        }
    }
    
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            readAvailableBytes(stream: aStream as! InputStream)
        case .endEncountered:
            stopChatSession()
        case .hasSpaceAvailable:
            print("has space available")
        case .errorOccurred:
            print("error occurred")
        default:
            print("some other event")
        }
    }
    private func readAvailableBytes(stream: InputStream) {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: maxReadLength)
        while stream.hasBytesAvailable {
            let numberOfBytesRead = inputStream.read(buffer, maxLength: maxReadLength)
            guard numberOfBytesRead > 0, stream.streamError == nil else {
                break
            }
            if let message = processedMessageString(buffer: buffer, length: numberOfBytesRead) {
                delegate?.receivedMessage(message: message)
            }
        }
    }
    
    private func processedMessageString(buffer: UnsafeMutablePointer<UInt8>, length: Int) -> Message? {
        let rawString = String(bytesNoCopy: buffer, length: length, encoding: .ascii, freeWhenDone: true)
        guard
            let stringArray = rawString?.components(separatedBy: ":"),
            let name = stringArray.first,
            let message = stringArray.last
            else { return nil }
        let messageSender: MessageSender = name == username ? .ourself : .someoneElse
        return Message(message: message, messageSender: messageSender, username: name)
    }
    
    func sendMessage(message: String) {
        let data = self.message(message)
        send(data)
    }
    
    func stopChatSession() {
        inputStream.close()
        outputStream.close()
    }
}
