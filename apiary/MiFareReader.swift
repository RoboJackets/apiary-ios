//
//  MiFareReader.swift
//  apiary
//
//  Created by Todd Hayes on 6/22/24.
//


import UIKit
import CoreNFC

class MiFareReader: UITableViewController, NFCTagReaderSessionDelegate {
    
    // MARK: - Properties
    var readerSession: NFCTagReaderSession?
    @IBOutlet weak var couponText: UITextField!
    
    // MARK: - Actions
    @IBAction func scanCoupon(_ sender: Any) {
        guard NFCNDEFReaderSession.readingAvailable else {
            let alertController = UIAlertController(
                title: "Scanning Not Supported",
                message: "This device doesn't support tag scanning.",
                preferredStyle: .alert
            )
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alertController, animated: true, completion: nil)
            return
        }
        
        readerSession = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: nil)
        readerSession?.alertMessage = "Hold your iPhone near an NFC fish tag."
        readerSession?.begin()
    }
    
    func updateWithCouponCode(_ code: String) {
        DispatchQueue.main.async {
            self.couponText.text = code
        }
    }
    
    // MARK: - Private helper functions
    func sendReadTagCommand(_ data: Data, to tag: NFCMiFareTag, _ completionHandler: @escaping (Data) -> Void) {
        if #available(iOS 14, *) {
            tag.sendMiFareCommand(commandPacket: data) { (result: Result<Data, Error>) in
                switch result {
                case .success(let response):
                    completionHandler(response)
                case .failure(let error):
                    self.readerSession?.invalidate(errorMessage: "Read tag error: \(error.localizedDescription). Please try again.")
                }
            }
        } else {
            tag.sendMiFareCommand(commandPacket: data) { (response: Data, optionalError: Error?) in
                guard let error = optionalError else {
                    completionHandler(response)
                    return
                }
                
                self.readerSession?.invalidate(errorMessage: "Read tag error: \(error.localizedDescription). Please try again.")
            }
        }
    }
    
    func readCouponCode(from tag: NFCTag) {
        guard case let .miFare(mifareTag) = tag else {
            return
        }
        
        DispatchQueue.global().async {
            let select_application_aupd: [UInt8] = [0x90, 0x5a, 0x00, 0x00, 3, 0xcd, 0xbb, 0xbb, 0x00]
            let read_file_aupd: [UInt8] = [0x90, 0xbd, 0x00, 0x00, 0x07, 0x01, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00]
            // select file
            self.sendReadTagCommand(Data(select_application_aupd), to: mifareTag) { (responseFromSelect: Data) in }
            // read file data
            self.sendReadTagCommand(Data(read_file_aupd), to: mifareTag) { (responseFromRead: Data) in
                // let base64Data: String = responseFromRead.base64EncodedString()
                // GTID is first 14 base64 characters
                // why can't swift let me read a string
                let decodedData = String(data: responseFromRead, encoding: .ascii)
                if let realString = decodedData {
                   // have non optional string now, need to truncate GTID
                    let index = realString.index(realString.startIndex, offsetBy: 9)
                    let gtid = String(realString[..<index])
                    self.readerSession?.invalidate(errorMessage: "Decoded response: \(gtid)")
                } else {
                    self.readerSession?.invalidate(errorMessage: "Failed to decode data from buzzcard")
                }
            }
        }
    }

    // MARK: - NFCTagReaderSessionDelegate
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // If necessary, you may perform additional operations on session start.
        // At this point RF polling is enabled.
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // If necessary, you may handle the error. Note the session is no longer valid.
        // You must create a new session to restart RF polling.
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        var tag: NFCTag? = nil
        
        for nfcTag in tags {
            tag = nfcTag
            break
        }
        
        if tag == nil {
            session.invalidate(errorMessage: "No valid coupon found.")
            return
        }
        
        session.connect(to: tag!) { (error: Error?) in
            if error != nil {
                session.invalidate(errorMessage: "Connection error. Please try again.")
                return
            }
            self.readCouponCode(from: tag!)
        }
    }
}


