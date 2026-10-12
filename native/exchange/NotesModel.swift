// Official notes-only preservation. SPDX-License-Identifier: GPL-3.0-only
import AuthenticationServices
import CryptoKit
import Darwin
import Foundation

enum NotesFailure: Error {
    case invalidTransport, alreadyAttempted, transportMissing, transportAccessDenied, journalLookupFailed, nativeReviewExpired
    var safeCode: String {
        switch self {
        case .invalidTransport: return "exchange_notes_plan_invalid"
        case .alreadyAttempted: return "exchange_notes_attempt_requires_review"
        case .transportMissing: return "exchange_notes_transport_missing"
        case .transportAccessDenied: return "exchange_notes_transport_access_denied"
        case .journalLookupFailed: return "exchange_notes_attempt_lookup_failed"
        case .nativeReviewExpired: return "exchange_native_review_expired"
        }
    }
}
func notesFailureReport(_ error: Error, attemptStarted: Bool, exchangeAPIInvoked: Bool, guiLaunched: Bool) -> [String:Any] {
    let native = error as NSError
    let failure = error as? NotesFailure
    let detail: String
    switch failure {
    case .nativeReviewExpired:
        detail = "本批次核对已超过 1 小时。须重新核对并准备新批次，旧批次和失败记录保留。"
    case .alreadyAttempted:
        detail = "此批次已有交接记录，须先核对结果；重复导入已阻止。"
    case .transportMissing:
        detail = "未找到私有资料批次，请先准备对应批次。"
    case .transportAccessDenied:
        detail = "无法访问私有资料批次，请核对权限；旧记录保留。"
    case .journalLookupFailed:
        detail = "无法确认此前的交接记录，已停止；请核对记录后再处理。"
    case .invalidTransport:
        detail = "资料批次验证失败，请核对内容及权限；旧记录保留。"
    case nil:
        detail = exchangeAPIInvoked ? "交接未完成（\(native.domain)，\(native.code)）。保留本次记录，须先核对结果。" : "资料批次验证失败（\(native.domain)，\(native.code)）；旧记录保留。"
    }
    return ["error":failure?.safeCode ?? (exchangeAPIInvoked ? "exchange_operation_failed" : "exchange_notes_plan_invalid"),
            "error_domain":native.domain,"error_code":native.code,
            "user_message":(exchangeAPIInvoked ? "" : "未调用 Apple 交接。") + detail,
            "failure_stage":exchangeAPIInvoked ? "apple_exchange" : "local_preflight",
            "attempt_started":attemptStarted,"exchange_api_invoked":exchangeAPIInvoked,
            "gui_launched":guiLaunched,"export_api_completed":false,"native_apple_import_verified":false]
}
struct NotesTOTP: Codable, Equatable {
    let secret_base64: String
    let period: Int
    let digits: Int
    let username: String
    let algorithm: String
    let issuer: String?
    var valid: Bool {
        guard let secret = Data(base64Encoded:secret_base64), !secret.isEmpty, secret.count <= 1024,
              secret.base64EncodedString() == secret_base64, (1...65535).contains(period),
              (1...10).contains(digits), ["SHA1","SHA256","SHA512"].contains(algorithm),
              !username.isEmpty, username.utf16.count <= 4096, !username.contains("\0") else { return false }
        return issuer == nil || (issuer!.utf16.count <= 4096 && !issuer!.contains("\0"))
    }
    func credential() -> ASImportableCredential.TOTP {
        .init(secret:Data(base64Encoded:secret_base64)!,period:UInt16(period),digits:UInt16(digits),
              userName:username,algorithm:algorithm == "SHA256" ? .sha256 : algorithm == "SHA512" ? .sha512 : .sha1,issuer:issuer)
    }
}
struct NotesRecord: Codable, Equatable {
    let id: String
    let title: String
    let notes: String
    let source_ids: [String]
    let part_index: Int
    let part_count: Int
    let source_payload_sha256: String
    let username: String?
    let password: String?
    let urls: [String]?
    let kind: String?
    let totp: NotesTOTP?
}
struct NotesBundle: Codable, Equatable {
    let format: String
    let plan_sha256: String
    let created_timestamp: Int
    let source_count: Int
    let items: [NotesRecord]
    let reviewed_snapshot_sha256: String?
    let reviewed_timestamp: Int?
    var native: Bool { format == "apw-passwords-native-v1" }
    var otpOnly: Bool { format == "apw-passwords-totp-v1" }
    var boundOTPCount: Int { native ? items.filter {$0.kind == "bound_otp_login"}.count : 0 }
    var scoped: Bool { native || otpOnly }
    static func transportName(native: Bool = false, otpOnly: Bool = false) -> String {
        otpOnly ? "otp-preservation.json" : native ? "credentials-preservation.json" : "notes-preservation.json"
    }
    static func attemptName(native: Bool = false, otpOnly: Bool = false) -> String {
        otpOnly ? "otp-attempt.json" : native ? "credentials-attempt.json" : "notes-attempt.json"
    }
    static var root: URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("apw-exchange-probe",isDirectory:true) }
    static var stagedURL: URL { root.appendingPathComponent("notes-preservation.json") }
    static var journalURL: URL { root.appendingPathComponent("notes-attempt.json") }
    static func directory(batch: String?) -> URL {
        guard let batch = batch else { return root }
        return root.appendingPathComponent("batches",isDirectory:true).appendingPathComponent(batch,isDirectory:true)
    }
    static func protectedBytes(_ url: URL) throws -> Data {
        let fd = open(url.path,O_RDONLY | O_NOFOLLOW)
        if fd < 0 {
            let failure = errno
            if failure == ENOENT { throw NotesFailure.transportMissing }
            if failure == EACCES || failure == EPERM { throw NotesFailure.transportAccessDenied }
            throw NotesFailure.invalidTransport
        }
        let handle = FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        var before = stat(), after = stat()
        guard fstat(fd,&before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_uid == getuid(),
              before.st_mode & 0o077 == 0, before.st_nlink == 1, before.st_size > 0, before.st_size <= 32 * 1024 * 1024 else { throw NotesFailure.invalidTransport }
        let bytes = try handle.readToEnd() ?? Data()
        guard fstat(fd,&after) == 0, after.st_size == before.st_size, bytes.count == before.st_size,
              after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec, after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec else { throw NotesFailure.invalidTransport }
        return bytes
    }
    static func load(_ url: URL, enforceReviewAge: Bool = true) throws -> (NotesBundle,String) {
        let bytes = try protectedBytes(url)
        let bundle = try JSONDecoder().decode(NotesBundle.self,from:bytes)
        let sources = Set(bundle.items.flatMap(\.source_ids))
        guard ["apw-passwords-notes-v1","apw-passwords-native-v1","apw-passwords-totp-v1"].contains(bundle.format), bundle.plan_sha256.count == 64,
              bundle.plan_sha256.allSatisfy({ $0.isHexDigit }), bundle.created_timestamp > 0,
              !bundle.items.isEmpty, bundle.items.count <= 3000, bundle.source_count == sources.count,
              Set(bundle.items.map(\.id)).count == bundle.items.count,
              Set(bundle.items.map(\.title)).count == bundle.items.count,
              bundle.items.allSatisfy({ item in
                  item.id.hasPrefix(bundle.otpOnly ? "apw-otp-apple-" : bundle.native ? "apw-native-apple-" : "apw-notes-apple-") && !item.title.isEmpty && item.title.utf16.count <= 512 &&
                  !item.notes.isEmpty && item.notes.utf16.count <= 4096 && !item.notes.contains("\0") &&
                  !item.source_ids.isEmpty && item.source_ids.allSatisfy({ item.notes.contains($0) }) &&
                  item.part_index > 0 && item.part_index <= item.part_count &&
                  item.source_payload_sha256.count == 64 && item.source_payload_sha256.allSatisfy({ $0.isHexDigit })
              }) else { throw NotesFailure.invalidTransport }
        if bundle.scoped {
            guard bundle.items.count <= 100, let stamp = bundle.reviewed_timestamp, stamp > 0,
                  Double(stamp) <= Date().timeIntervalSince1970 + 60,
                  let snapshot = bundle.reviewed_snapshot_sha256, snapshot.count == 64, snapshot.allSatisfy({$0.isHexDigit}),
                  bundle.items.allSatisfy({ item in
                      if bundle.otpOnly {
                          guard item.kind == "verification_code", item.username == nil, item.password == nil,
                                let config = item.totp, config.valid else { return false }
                      } else {
                          guard let user = item.username, !user.isEmpty, user.utf16.count <= 4096, !user.contains("\0"),
                                let password = item.password, password.utf16.count <= 4096, !password.contains("\0"),
                                let kind = item.kind, ["login","sso","bound_otp_login"].contains(kind), (kind != "sso" || password.isEmpty) else { return false }
                          if kind == "bound_otp_login" {
                              guard let config = item.totp, config.valid, config.username == user else { return false }
                          } else if item.totp != nil { return false }
                      }
                      guard let urls = item.urls, !urls.isEmpty, urls.count <= 100 else { return false }
                      return urls.allSatisfy { raw in
                          guard raw.utf16.count <= 8192, let u = URL(string:raw), ["http","https"].contains(u.scheme ?? ""),
                                let host = u.host, !host.isEmpty, u.user == nil, u.password == nil else { return false }
                          return true
                      }
                  }) else { throw NotesFailure.invalidTransport }
            if enforceReviewAge { try bundle.requireCurrentNativeReview() }
        } else if bundle.items.contains(where:{$0.username != nil || $0.password != nil || $0.urls != nil || $0.kind != nil || $0.totp != nil}) {
            throw NotesFailure.invalidTransport
        }
        let hash = SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined()
        return (bundle,hash)
    }
    private func requireCurrentNativeReview() throws {
        if scoped, let stamp = reviewed_timestamp,
           Date().timeIntervalSince1970 - Double(stamp) > 3600 {
            throw NotesFailure.nativeReviewExpired
        }
    }
    func credentialData(version: ASExportedCredentialData.FormatVersion = .v1) -> ASExportedCredentialData {
        let date = Date(timeIntervalSince1970:Double(created_timestamp))
        let records = items.map { item -> ASImportableItem in
            var credentials:[ASImportableCredential] = [.note(.init(content:ExchangeDemo.field(item.notes)))]
            var scope: ASImportableCredentialScope?
            if native {
                credentials.insert(.basicAuthentication(.init(userName:ExchangeDemo.field(item.username!),password:item.password!.isEmpty ? nil : ExchangeDemo.field(item.password!,concealed:true))),at:0)
                if let config = item.totp { credentials.append(.totp(config.credential())) }
                scope = ASImportableCredentialScope(urls:item.urls!.map {URL(string:$0)!})
            }
            if otpOnly {
                credentials.insert(.totp(item.totp!.credential()),at:0)
                scope = ASImportableCredentialScope(urls:item.urls!.map {URL(string:$0)!})
            }
            return ASImportableItem(id:Data(item.id.utf8),created:date,lastModified:date,title:item.title,scope:scope,credentials:credentials,tags:["1Password 迁移资料"])
        }
        let account = ASImportableAccount(id:Data("apw-source-linked-notes-v1".utf8),userName:"1Password 资料迁移",email:"",collections:[],items:records)
        return ASExportedCredentialData(accounts:[account],formatVersion:version,exporterRelyingPartyIdentifier:"apw.invalid",exporterDisplayName:"apw · 1Password 资料迁移",timestamp:date)
    }
    static func totps(_ item: ASImportableItem) -> [ASImportableCredential.TOTP] {
        item.credentials.compactMap { if case .totp(let value) = $0 { return value }; return nil }
    }
    func validationReport() throws -> [String:Any] {
        let expected = credentialData()
        let roundtrip = try JSONDecoder().decode(ASExportedCredentialData.self,from:JSONEncoder().encode(expected))
        let records = roundtrip.accounts.flatMap(\.items)
        let exact = roundtrip == expected && records.map(ExchangeDemo.notes) == items.map { [$0.notes] }
        return ["codec_exact":exact,"note_count":records.count,"source_count":source_count,
                "bound_otp_count":boundOTPCount,
                "same_item_binding_exact":zip(items,records).allSatisfy { item, record in
                    item.kind != "bound_otp_login" || (ExchangeDemo.authentication(record).count == 1 &&
                    ExchangeDemo.authentication(record)[0].userName?.value == item.totp?.username &&
                    Self.totps(record) == [item.totp!.credential()] && record.scope?.urls == item.urls!.map {URL(string:$0)!})
                },
                "basic_authentication_count":records.flatMap(ExchangeDemo.authentication).count,
                "totp_count":records.flatMap(Self.totps).count,
                "scope_count":records.filter { $0.scope != nil }.count,"plan_sha256":plan_sha256,
                "max_note_utf16":items.map { $0.notes.utf16.count }.max() ?? 0,
                "exchange_api_invoked":false,"gui_launched":false,"native_apple_import_verified":false,
                "whole_vault_verified":false,"real_user_values_retained":false]
    }
    static func preflight(_ url: URL = stagedURL, native: Bool = false, otpOnly: Bool = false) throws -> [String:Any] {
        // Validate structure and protected bytes first. A prior attempt must
        // remain visible after the review expires; expiry cannot authorize resend.
        let (bundle,digest) = try load(url,enforceReviewAge:false)
        var report = try bundle.validationReport()
        guard !(native && otpOnly), bundle.native == native, bundle.otpOnly == otpOnly, report["codec_exact"] as? Bool == true,
              report["basic_authentication_count"] as? Int == (native ? bundle.items.count : 0),
              report["totp_count"] as? Int == (otpOnly ? bundle.items.count : bundle.boundOTPCount),
              report["scope_count"] as? Int == (native || otpOnly ? bundle.items.count : 0) else { throw NotesFailure.invalidTransport }
        // lstat includes dangling symlinks; an inaccessible lookup is unknown,
        // never authorization to resend an existing batch.
        let journal = url.deletingLastPathComponent().appendingPathComponent(attemptName(native:native,otpOnly:otpOnly))
        var info = stat()
        if lstat(journal.path,&info) == 0 { throw NotesFailure.alreadyAttempted }
        guard errno == ENOENT else { throw NotesFailure.journalLookupFailed }
        try bundle.requireCurrentNativeReview()
        report["checked"] = true
        report["ready_to_import"] = true
        report["attempt_present"] = false
        report["transport_sha256"] = digest
        return report
    }
    func inspect(_ received: ASExportedCredentialData) -> [String:Any] {
        let incoming = received.accounts.flatMap(\.items)
        var matched = 0, missing = 0, duplicated = 0, changed = 0
        for expected in items {
            let candidates = incoming.filter { $0.title == expected.title }
            if candidates.isEmpty { missing += 1; continue }
            if candidates.count != 1 { duplicated += 1; continue }
            let emptyCredentials = ExchangeDemo.authentication(candidates[0]).allSatisfy { ($0.userName?.value ?? "").isEmpty && ($0.password?.value ?? "").isEmpty }
            let otpExact = !otpOnly || (Self.totps(candidates[0]) == [expected.totp!.credential()] && candidates[0].scope?.urls == expected.urls!.map {URL(string:$0)!})
            if ExchangeDemo.notes(candidates[0]) == [expected.notes] && emptyCredentials && otpExact { matched += 1 } else { changed += 1 }
        }
        return ["note_count":items.count,"source_count":source_count,"matched":matched,"missing":missing,"duplicated":duplicated,"changed":changed,
                "data_roundtrip_matches":matched == items.count,"source_review_required":true,
                "native_apple_import_verified":false,"whole_vault_verified":false,"real_user_values_retained":false]
    }
    private static func protectedRoot(_ directory: URL) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        var info = stat()
        guard lstat(directory.path,&info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw NotesFailure.invalidTransport }
    }
    static func beginAttempt(digest: String, directory: URL = root, native: Bool = false, otpOnly: Bool = false) throws {
        try protectedRoot(directory)
        let path = directory.appendingPathComponent(attemptName(native:native,otpOnly:otpOnly))
        let fd = open(path.path,O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,0o600)
        guard fd >= 0 else { throw NotesFailure.alreadyAttempted }
        let handle = FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        let bytes = try JSONSerialization.data(withJSONObject:["transport_sha256":digest,"phase":"requested_before_api","native_apple_import_verified":false])
        try handle.write(contentsOf:bytes); try handle.synchronize()
    }
    static func finishAttempt(digest: String, phase: String, directory: URL = root, native: Bool = false, otpOnly: Bool = false) throws {
        try protectedRoot(directory)
        let path = directory.appendingPathComponent(attemptName(native:native,otpOnly:otpOnly))
        let current = try JSONSerialization.jsonObject(with:protectedBytes(path)) as? [String:Any]
        guard current?["transport_sha256"] as? String == digest else { throw NotesFailure.invalidTransport }
        let bytes = try JSONSerialization.data(withJSONObject:["transport_sha256":digest,"phase":phase,"native_apple_import_verified":false])
        try bytes.write(to:path,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)
    }
    static func journalSelfTest(directory: URL) throws -> [String:Any] {
        let digest = String(repeating:"0",count:64)
        try beginAttempt(digest:digest,directory:directory)
        var duplicateBlocked = false
        do { try beginAttempt(digest:digest,directory:directory) } catch NotesFailure.alreadyAttempted { duplicateBlocked = true }
        try finishAttempt(digest:digest,phase:"api_completed_verification_pending",directory:directory)
        let value = try JSONSerialization.jsonObject(with:protectedBytes(directory.appendingPathComponent("notes-attempt.json"))) as? [String:Any]
        return ["duplicate_attempt_blocked":duplicateBlocked,"completed_phase_recorded":value?["phase"] as? String == "api_completed_verification_pending",
                "exchange_api_invoked":false,"gui_launched":false,"native_apple_import_verified":false]
    }
}
