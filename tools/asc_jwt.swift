// Prints a 15-minute App Store Connect API token (key from ~/.appstoreconnect).
//   swiftc -O tools/asc_jwt.swift -o /tmp/asc && curl -H "Authorization: Bearer $(/tmp/asc)" https://api.appstoreconnect.apple.com/v1/...
import CryptoKit
import Foundation

let keyID = "ASC_KEY_ID"
let home = FileManager.default.homeDirectoryForCurrentUser
let issuer = try! String(contentsOf: home.appendingPathComponent(".appstoreconnect/issuer_id.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
let pem = try! String(contentsOf: home.appendingPathComponent(".appstoreconnect/private_keys/AuthKey_\(keyID).p8"), encoding: .utf8)
let key = try! P256.Signing.PrivateKey(pemRepresentation: pem)
func b64(_ d: Data) -> String { d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
let now = Int(Date().timeIntervalSince1970)
let header = b64(try! JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "JWT"]))
let payload = b64(try! JSONSerialization.data(withJSONObject: ["iss": issuer, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"]))
let sig = try! key.signature(for: Data("\(header).\(payload)".utf8))
print("\(header).\(payload).\(b64(sig.rawRepresentation))")
