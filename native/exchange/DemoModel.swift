// Optional official API trial for apw. SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AuthenticationServices
import CryptoKit
import Darwin

enum ExchangeOTPLoginDemo {
    static let marker = "APW_OTP_LOGIN_CONTROL_V1"
    static let username = "synthetic-bound-otp@example.invalid"
    static let password = "SYNTHETIC_BOUND_OTP_PASSWORD"
    static let website = "https://apw-otp-login-control-20261011.invalid/login"
    static var directory: URL { NotesBundle.root.appendingPathComponent("batches/otp-login-control-v1",isDirectory:true) }
    static func data(version: ASExportedCredentialData.FormatVersion = .v1) -> ASExportedCredentialData {
        let date = Date(timeIntervalSince1970:1_791_687_369)
        let login = ASImportableCredential.basicAuthentication(.init(userName:ExchangeDemo.field(username),password:ExchangeDemo.field(password,concealed:true)))
        let totp = ASImportableCredential.totp(.init(secret:Data("12345678901234567890".utf8),period:30,digits:6,userName:username,algorithm:.sha1,issuer:"apw synthetic bound OTP"))
        let item = ASImportableItem(id:Data("apw-otp-login-control-item-v1".utf8),created:date,lastModified:date,title:"apw API 测试 · 登录与验证码",scope:ASImportableCredentialScope(urls:[URL(string:website)!]),credentials:[login,totp,.note(.init(content:ExchangeDemo.field(marker)))],tags:["apw 合成测试"])
        let account = ASImportableAccount(id:Data("apw-otp-login-control-account-v1".utf8),userName:"apw synthetic OTP control",email:"synthetic@example.invalid",collections:[],items:[item])
        return ASExportedCredentialData(accounts:[account],formatVersion:version,exporterRelyingPartyIdentifier:"apw.invalid",exporterDisplayName:"apw 登录验证码测试",timestamp:date)
    }
    static func digest() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data:try encoder.encode(data())).map {String(format:"%02x",$0)}.joined()
    }
    static func preflight(directory: URL = directory) throws -> [String:Any] {
        var info = stat()
        if lstat(directory.path,&info) == 0 {
            guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw NotesFailure.invalidTransport }
        } else if errno != ENOENT { throw NotesFailure.journalLookupFailed }
        let journal = directory.appendingPathComponent("credentials-attempt.json")
        if lstat(journal.path,&info) == 0 { throw NotesFailure.alreadyAttempted }
        guard errno == ENOENT else { throw NotesFailure.journalLookupFailed }
        let expected = data()
        let received = try JSONDecoder().decode(ASExportedCredentialData.self,from:JSONEncoder().encode(expected))
        let items = received.accounts.flatMap(\.items)
        let exact = received == expected && items.count == 1 && ExchangeDemo.authentication(items[0]).count == 1 && NotesBundle.totps(items[0]).count == 1 && ExchangeDemo.notes(items[0]) == [marker] && items[0].scope?.urls == [URL(string:website)!]
        guard exact else { throw NotesFailure.invalidTransport }
        return ["codec_exact":true,"same_item_binding_exact":true,"test_record_count":1,
                "fixture_sha256":try digest(),
                "basic_authentication_count":1,"totp_count":1,"scope_count":1,
                "synthetic_only":true,"real_user_secret_used":false,"native_reads":0,
                "ready_to_import":true,"gui_launched":false,"exchange_api_invoked":false,
                "native_apple_import_verified":false,"native_totp_import_verified":false]
    }
    static func inspect(_ received: ASExportedCredentialData) -> [String:Any] {
        let expected = data().accounts[0].items[0]
        let items = received.accounts.flatMap(\.items).filter {ExchangeDemo.notes($0).contains(marker)}
        let exact = items.count == 1 && ExchangeDemo.authentication(items[0]) == ExchangeDemo.authentication(expected) && NotesBundle.totps(items[0]) == NotesBundle.totps(expected) && items[0].scope == expected.scope && ExchangeDemo.notes(items[0]) == [marker]
        return ["data_roundtrip_matches":exact,"source_review_required":true,
                "test_record_count":items.count,"native_apple_import_verified":false,
                "native_totp_import_verified":false,"real_user_values_retained":false]
    }
}

enum ExchangeDemo {
    static let prefix = "apw API 测试 · "
    static let marker = "APW_EXCHANGE_SYNTHETIC_V1"
    static func field(_ value: String, concealed: Bool = false) -> ASImportableEditableField {
        ASImportableEditableField(id: nil, fieldType: concealed ? .concealedString : .string, value: value)
    }
    static func data(version: ASExportedCredentialData.FormatVersion = .v1) -> ASExportedCredentialData {
        let date = Date(timeIntervalSince1970: 1_791_504_000)
        let scope = ASImportableCredentialScope(urls: [URL(string: "https://apw-exchange-demo.invalid/login")!, URL(string: "https://www.apw-exchange-demo.invalid")!])
        func item(_ id: String, _ suffix: String, _ credentials: [ASImportableCredential], scoped: Bool) -> ASImportableItem {
            ASImportableItem(id: Data(id.utf8), created: date, lastModified: date, title: prefix + suffix, scope: scoped ? scope : nil, credentials: credentials, tags: ["apw 合成测试"])
        }
        let password = item("apw-demo-password-v1", "密码与备注", [
            .basicAuthentication(.init(userName: field("synthetic-password@example.invalid"), password: field("SYNTHETIC_OWN_PASSWORD", concealed: true))),
            .note(.init(content: field(marker + "\n来源：password\n原备注：中文、emoji 😀、第二行\n自定义字段：SYNTHETIC_CUSTOM_VALUE")))
        ], scoped: true)
        let sso = item("apw-demo-sso-v1", "SSO 与备注", [
            .basicAuthentication(.init(userName: field("synthetic-google@example.invalid"), password: nil)),
            .note(.init(content: field(marker + "\n来源：sso\n登录方式：Google\n提供方账号：synthetic-google@example.invalid\n不包含提供方密码")))
        ], scoped: true)
        let note = item("apw-demo-note-v1", "独立备注", [
            .note(.init(content: field(marker + "\n来源：note\nAPI key：SYNTHETIC_API_KEY\n多行资料：\n第一行\n第二行 😀")))
        ], scoped: false)
        let account = ASImportableAccount(id: Data("apw-synthetic-account-v1".utf8), userName: "apw synthetic trial", email: "synthetic@example.invalid", collections: [], items: [password,sso,note])
        return ASExportedCredentialData(accounts: [account], formatVersion: version, exporterRelyingPartyIdentifier: "apw.invalid", exporterDisplayName: "apw API 测试", timestamp: date)
    }
    static func notes(_ item: ASImportableItem) -> [String] {
        item.credentials.compactMap { if case .note(let note) = $0 { return note.content.value }; return nil }
    }
    static func authentication(_ item: ASImportableItem) -> [ASImportableCredential.BasicAuthentication] {
        item.credentials.compactMap { if case .basicAuthentication(let value) = $0 { return value }; return nil }
    }
    static func selfTest() throws -> [String:Any] {
        let expected = data(); let encoded = try JSONEncoder().encode(expected)
        let received = try JSONDecoder().decode(ASExportedCredentialData.self, from: encoded)
        let items = received.accounts.flatMap(\.items)
        let longText = String(repeating: "中文😀\n", count: 2_000)
        let longNote = ASImportableCredential.Note(content: field(longText))
        let longDecoded = try JSONDecoder().decode(ASImportableCredential.Note.self, from: JSONEncoder().encode(longNote))
        func withItems(_ items: [ASImportableItem]) -> ASExportedCredentialData {
            let original = expected.accounts[0]
            let account = ASImportableAccount(id: original.id, userName: original.userName, email: original.email, collections: original.collections, items: items)
            return ASExportedCredentialData(accounts: [account], formatVersion: expected.formatVersion, exporterRelyingPartyIdentifier: expected.exporterRelyingPartyIdentifier, exporterDisplayName: expected.exporterDisplayName, timestamp: expected.timestamp)
        }
        let changedSSO = ASImportableItem(id: items[1].id, created: items[1].created, lastModified: items[1].lastModified, title: items[1].title, scope: items[1].scope, credentials: [
            .basicAuthentication(.init(userName: field("synthetic-google@example.invalid"), password: field("SYNTHETIC_WRONG_PASSWORD", concealed: true))),
            items[1].credentials[1]
        ], tags: items[1].tags)
        let echoed = inspect(received)
        let missing = inspect(withItems(Array(items.prefix(2))))
        let duplicate = inspect(withItems(items + [items[0]]))
        let changed = inspect(withItems([items[0], changedSSO, items[2]]))
        let checks: [[String:Any]] = [
            ["name":"Apple credential-data Codable round trip retains all fields", "passed":received == expected],
            ["name":"password and Unicode multiline notes retain exact own values", "passed":authentication(items[0]).first?.password?.value == "SYNTHETIC_OWN_PASSWORD" && notes(items[0]) == notes(expected.accounts[0].items[0])],
            ["name":"SSO account contains no provider password or fabricated password", "passed":authentication(items[1]).first?.userName?.value == "synthetic-google@example.invalid" && authentication(items[1]).first?.password == nil],
            ["name":"notes-only record has no login credential and no invented website", "passed":authentication(items[2]).isEmpty && items[2].scope == nil && items[2].credentials.count == 1],
            ["name":"both scope URLs survive the official data format", "passed":items[0].scope?.urls.count == 2 && items[0].scope == expected.accounts[0].items[0].scope],
            ["name":"long Unicode note is not truncated by the official codec", "passed":longDecoded.content.value == longText],
            ["name":"trial payload contains exactly three synthetic items", "passed":items.count == 3 && items.allSatisfy { $0.title.hasPrefix(prefix) && notes($0).contains(where: { $0.contains(marker) }) }],
            ["name":"matching own payload is not proof of Apple import", "passed":echoed["data_roundtrip_matches"] as? Bool == true && echoed["native_apple_import_verified"] as? Bool == false && echoed["source_review_required"] as? Bool == true],
            ["name":"missing notes-only record cannot pass", "passed":missing["passed"] as? Bool == false && missing["native_apple_import_verified"] as? Bool == false],
            ["name":"duplicate test identity cannot pass", "passed":duplicate["passed"] as? Bool == false && duplicate["native_apple_import_verified"] as? Bool == false],
            ["name":"fabricated provider password cannot pass", "passed":changed["passed"] as? Bool == false && changed["native_apple_import_verified"] as? Bool == false]
        ]
        return ["passed":checks.allSatisfy { $0["passed"] as? Bool == true }, "checks":checks,"fixture_count":items.count,"exchange_api_invoked":false,"real_user_secret_used":false]
    }
    static func inspect(_ received: ASExportedCredentialData) -> [String:Any] {
        let expected = data().accounts[0].items
        // Never retain or print non-test credential contents, even if all were sent.
        let tests = received.accounts.flatMap(\.items).filter { $0.title.hasPrefix(prefix) && notes($0).contains(where: { $0.contains(marker) }) }
        let rows: [[String:Any]] = expected.map { source in
            let matches = tests.filter { $0.title == source.title }
            guard matches.count == 1, let target = matches.first else { return ["case":source.id == expected[0].id ? "password_notes" : source.id == expected[1].id ? "sso_notes" : "notes_only", "match_count":matches.count,"passed":false] }
            let notesMatch = notes(target) == notes(source)
            let credentialMatch = authentication(target) == authentication(source)
            let scopeMatch = target.scope == source.scope
            return ["case":source.id == expected[0].id ? "password_notes" : source.id == expected[1].id ? "sso_notes" : "notes_only", "match_count":1,"notes_exact":notesMatch,"credentials_exact":credentialMatch,"scope_exact":scopeMatch,"source_id_preserved":target.id == source.id,"passed":notesMatch && credentialMatch && scopeMatch]
        }
        let matches = rows.allSatisfy { $0["passed"] as? Bool == true }
        // The payload's exporter name/RP is descriptive data, not attestation.
        // A matching self-echo or unreviewed source must not prove Apple import.
        return ["passed":matches,"data_roundtrip_matches":matches,"checks":rows,"test_record_count":tests.count,"native_apple_import_verified":false,"source_review_required":true,"real_user_values_retained":false]
    }
}
