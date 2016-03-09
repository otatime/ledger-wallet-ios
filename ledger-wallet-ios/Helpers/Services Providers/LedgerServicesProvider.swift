//
//  LedgerServicesProvider.swift
//  ledger-wallet-ios
//
//  Created by Nicolas Bigot on 08/01/2016.
//  Copyright © 2016 Ledger. All rights reserved.
//

import Foundation
import CoreBluetooth

private enum LedgerAPIHeaderFields: String {
    
    case Platform = "X-Ledger-Platform"
    case Environment = "X-Ledger-Environment"
    case Locale = "X-Ledger-Locale"
    
}

struct LedgerServicesProvider: ServicesProviderType {
    
    let name = "Ledger Services Provider"
    let coinNetwork: CoinNetworkType
    
    // MARK: Base URLs
    
    let websocketBaseURL = NSURL(string: "wss://ws.ledgerwallet.com")!
    let APIBaseURL = NSURL(string: "https://api.ledgerwallet.com")!
    let supportBaseURL = NSURL(string: "http://support.ledgerwallet.com")!
    
    // MARK: Endpoint URLs
    
    var walletEventsWebsocketURL: NSURL {
        let path = "/blockchain/\(coinNetwork.acronym)/ws"
        return NSURL(string: path, relativeToURL: websocketBaseURL)!
    }
    
    func walletTransactionsURLForAddresses(addresses: [String]) -> NSURL {
        let path = "/blockchain/\(coinNetwork.acronym)/addresses/\(addresses.joinWithSeparator(","))/transactions"
        return NSURL(string: path, relativeToURL: APIBaseURL)!
    }
    
    func walletRawTransactionURLFromHash(hash: String) -> NSURL {
        let path = "/blockchain/\(coinNetwork.acronym)/transactions/\(hash)/hex"
        return NSURL(string: path, relativeToURL: APIBaseURL)!
    }
    
    func walletPushRawTransactionURL() -> NSURL {
        let path = "/blockchain/\(coinNetwork.acronym)/pushtx"
        return NSURL(string: path, relativeToURL: APIBaseURL)!
    }
    
    var m2FAChannelsWebsocketURL: NSURL {
        return NSURL(string: "/2fa/channels", relativeToURL: websocketBaseURL)!
    }
    
    func m2FAPushTokensURLForPairingId(pairingId: String) -> NSURL {
        let path = "/2fa/pairings/\(pairingId)/push_token"
        return NSURL(string: path, relativeToURL: APIBaseURL)!
    }
    
    // MARK: Attestation keys
    
    let betaAttestationKey = AttestationKey(batchID: 0x00, derivationID: 0x01, publicKey: "04e69fd3c044865200e66f124b5ea237c918503931bee070edfcab79a00a25d6b5a09afbee902b4b763ecf1f9c25f82d6b0cf72bce3faf98523a1066948f1a395f") // beta
    
    let attestationKeys = [
        AttestationKey(batchID: 0x01, derivationID: 0x01, publicKey: "04223314cdffec8740150afe46db3575fae840362b137316c0d222a071607d61b2fd40abb2652a7fea20e3bb3e64dc6d495d59823d143c53c4fe4059c5ff16e406"), // production (pre 1.4.11)
        AttestationKey(batchID: 0x02, derivationID: 0x01, publicKey: "04c370d4013107a98dfef01d6db5bb3419deb9299535f0be47f05939a78b314a3c29b51fcaa9b3d46fa382c995456af50cd57fb017c0ce05e4a31864a79b8fbfd6")  // production (post 1.4.11)
    ]
    
    // MARK: HTTP headers
    
    var httpHeaders: [String: String] {
        var headers: [String: String] = [
            LedgerAPIHeaderFields.Platform.rawValue: "ios",
            LedgerAPIHeaderFields.Locale.rawValue: NSLocale.currentLocale().localeIdentifier
        ]
        #if DEBUG
            headers[LedgerAPIHeaderFields.Environment.rawValue] = "dev"
        #else
            headers[LedgerAPIHeaderFields.Environment.rawValue] = "prod"
        #endif
        return headers
    }
    
    // MARK: Device descriptors

    var remoteDeviceDescriptors: [RemoteDeviceDescriptorType] {
        var devices: [RemoteDeviceDescriptorType] = []
        
        // Ledger Blue
        do {
            let deviceService = CBMutableService(type: CBUUID(string: "D973F2E0-B19E-11E2-9E96-0800200C9A66"), primary: true)
            let readCharacteristic = CBMutableCharacteristic(type: CBUUID(string: "D973F2E1-B19E-11E2-9E96-0800200C9A66"), properties: [.Notify], value: nil, permissions: [])
            let writeCharacteristic = CBMutableCharacteristic(type: CBUUID(string: "D973F2E2-B19E-11E2-9E96-0800200C9A66"), properties: [.Write], value: nil, permissions: [])
            let deviceDescriptor = RemoteBluetoothDeviceDescriptor(name: "Ledger", service: deviceService, readCharacteristic: readCharacteristic, writeCharacteristic: writeCharacteristic)
            devices.append(deviceDescriptor)
        }
        return devices
    }

    // MARK: Initialization
    
    init(coinNetwork: CoinNetworkType) {
        self.coinNetwork = coinNetwork
    }

}