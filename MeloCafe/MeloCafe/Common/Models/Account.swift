//
//  Account.swift
//  MeloCafe
//
//  Created by Stossy11 on 29/4/2026.
//

import Foundation
import SwiftUI

struct Account: Identifiable, Hashable {
    let persistentId: UInt32
    var miiName: String
    var birthYear: UInt16
    var birthMonth: UInt8
    var birthDay: UInt8
    var gender: Int
    var email: String
    var country: Int
    var isValidOnline: Bool

    var id: UInt32 { persistentId }
    var persistentIdHex: String { String(persistentId, radix: 16) }
    var displayName: String { miiName.isEmpty ? "default" : miiName }
    var displayNameWithId: String { "\(displayName) (\(persistentIdHex))" }

    init?(dictionary: [String: Any]) {
        guard let persistentId = dictionary["persistentId"] as? NSNumber else {
            return nil
        }

        self.persistentId = persistentId.uint32Value
        self.miiName = dictionary["miiName"] as? String ?? ""
        self.birthYear = (dictionary["birthYear"] as? NSNumber)?.uint16Value ?? 0
        self.birthMonth = (dictionary["birthMonth"] as? NSNumber)?.uint8Value ?? 0
        self.birthDay = (dictionary["birthDay"] as? NSNumber)?.uint8Value ?? 0
        self.gender = (dictionary["gender"] as? NSNumber)?.intValue ?? 0
        self.email = dictionary["email"] as? String ?? ""
        self.country = (dictionary["country"] as? NSNumber)?.intValue ?? 0
        self.isValidOnline = (dictionary["isValidOnline"] as? NSNumber)?.boolValue ?? false
    }
}

struct AccountCountry: Identifiable, Hashable {
    let code: Int
    let name: String

    var id: Int { code }

    init?(dictionary: [String: Any]) {
        guard let code = dictionary["code"] as? NSNumber else {
            return nil
        }

        self.code = code.intValue
        self.name = dictionary["name"] as? String ?? "\(code.intValue)"
    }
}
