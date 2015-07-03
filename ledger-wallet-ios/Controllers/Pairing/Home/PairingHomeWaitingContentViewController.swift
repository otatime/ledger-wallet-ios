//
//  PairingHomeWaitingContentViewController.swift
//  ledger-wallet-ios
//
//  Created by Nicolas Bigot on 10/02/2015.
//  Copyright (c) 2015 Ledger. All rights reserved.
//

import Foundation

final class PairingHomeWaitingContentViewController: PairingHomeBaseContentViewController {
    
    @IBAction private func managePairedDevicesButtonTouched() {
        Navigator.Pairing.presentListViewController(fromViewController: parentHomeViewController)
    }
    
}