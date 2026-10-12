// Optional official API trial for apw. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AuthenticationServices
import Foundation
import Security

let nativeArguments = Array(CommandLine.arguments.dropFirst())
let nativeBatch: String? = nativeArguments.count == 3 && nativeArguments[1] == "--batch" ? nativeArguments[2] : nil
if nativeArguments.contains("--batch") {
    guard let batch = nativeBatch, ["--notes-import","--notes-check","--credentials-import","--credentials-check","--credentials-startup-check","--otp-import","--otp-check"].contains(nativeArguments[0]),
          batch.range(of:"^[a-z0-9][a-z0-9-]{0,63}$",options:.regularExpression) != nil else {
        print("{\"error\":\"exchange_notes_batch_invalid\"}"); exit(2)
    }
}

func inspectProcess(_ pid: pid_t) -> [String:Any] {
    var guest: SecCode?
    let attributes = [kSecGuestAttributePid as String: NSNumber(value:pid)] as CFDictionary
    let lookup = SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest)
    guard lookup == errSecSuccess, let code = guest else {
        return ["inspection_succeeded":false,"running_pid":pid,"security_status":lookup]
    }
    var staticCode: SecStaticCode?
    let staticLookup = SecCodeCopyStaticCode(code, [], &staticCode)
    guard staticLookup == errSecSuccess, let signingCode = staticCode else {
        return ["inspection_succeeded":false,"running_pid":pid,"security_status":staticLookup]
    }
    var raw: CFDictionary?
    let flags = SecCSFlags(rawValue:kSecCSSigningInformation)
    let status = SecCodeCopySigningInformation(signingCode, flags, &raw)
    guard status == errSecSuccess, let info = raw as? [String:Any],
          let executable = info[kSecCodeInfoMainExecutable as String] as? URL else {
        return ["inspection_succeeded":false,"running_pid":pid,"security_status":status]
    }
    let ownExecutable = Bundle.main.executableURL!
    let owned = executable.resolvingSymlinksInPath() == ownExecutable.resolvingSymlinksInPath()
    guard owned else { return ["inspection_succeeded":true,"running_pid":pid,"matches_this_app":false] }
    // Entitlements may partly come from disk. Require dynamic code validity
    // before treating them as authorization for the actual running process.
    let validity = SecCodeCheckValidity(code, [], nil)
    let ent = info[kSecCodeInfoEntitlementsDict as String] as? [String:Any] ?? [:]
    let entitled = ent["com.apple.developer.authentication-services.autofill-credential-provider"] as? Bool == true
    return ["inspection_succeeded":true,"running_pid":pid,"matches_this_app":true,
            "runtime_matches_disk":validity == errSecSuccess,"security_status":validity,
            "process_has_required_entitlement":validity == errSecSuccess && entitled]
}

@MainActor final class ExchangeApp: NSObject, NSApplicationDelegate {
    let startupCheck = nativeArguments == ["--otp-login-demo-startup-check"] || (nativeBatch != nil && nativeArguments[0] == "--credentials-startup-check")
    let otpLoginDemoMode = nativeArguments == ["--otp-login-demo"] || nativeArguments == ["--otp-login-demo-startup-check"]
    let credentialsMode = nativeBatch != nil && ["--credentials-import","--credentials-startup-check"].contains(nativeArguments[0])
    let otpMode = nativeBatch != nil && nativeArguments[0] == "--otp-import"
    let notesMode = nativeArguments == ["--notes-import"] || (nativeBatch != nil && ["--notes-import","--credentials-import","--credentials-startup-check","--otp-import"].contains(nativeArguments[0]))
    var notesDirectory: URL { otpLoginDemoMode ? ExchangeOTPLoginDemo.directory : NotesBundle.directory(batch:nativeBatch) }
    var stagedURL: URL { notesDirectory.appendingPathComponent(NotesBundle.transportName(native:credentialsMode,otpOnly:otpMode)) }
    var journalURL: URL { notesDirectory.appendingPathComponent(NotesBundle.attemptName(native:credentialsMode || otpLoginDemoMode,otpOnly:otpMode)) }
    var otpLoginDigest: String?
    var notesBundle: NotesBundle?
    var notesDigest: String?
    var window: NSWindow!
    var status: NSTextField!
    var exportButton: NSButton!
    var exportManager: ASCredentialExportManager?
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x:0,y:0,width:590,height:320), styleMask:[.titled,.closable,.miniaturizable], backing:.buffered,defer:false)
        window.title = otpLoginDemoMode ? "apw · 登录与验证码对照测试" : otpMode ? "apw · 原生验证码交接" : credentialsMode ? "apw · 原生账号补齐" : notesMode ? "apw · 1Password 补充资料迁移" : "apw · 官方 API 迁移测试"
        let body = NSView(frame:NSRect(x:0,y:0,width:590,height:320)); window.contentView = body
        let text = NSTextField(wrappingLabelWithString:"仅测试 3 条合成资料：密码＋备注、空密码 SSO＋备注、独立备注。\n不会读取 1Password 导出，也不会批量修改你的现有账号。\n\n点击下方按钮后，由 Apple 系统引导你选择「密码」接收。\n是否实际保留备注，需将这 3 条测试资料回传给本组件验收。")
        var startupFailure: [String:Any]?
        if otpLoginDemoMode {
            text.stringValue = "仅测试一条全新的虚构登录：账号、密码、验证码放在同一条目。\n网站使用专用 .invalid 域名，不读取或发送真实资料。\n此前验证码批次和原账号保持不变。\n\n点击按钮，在 Apple 系统窗口选择「密码」接收。\n交接后仍须后台验收；若提示替换已有条目，请停止。"
            do { _ = try ExchangeOTPLoginDemo.preflight(); otpLoginDigest = try ExchangeOTPLoginDemo.digest() }
            catch { startupFailure = notesFailureReport(error,attemptStarted:false,exchangeAPIInvoked:false,guiLaunched:true) }
        }
        if notesMode {
            do {
                let (bundle,digest) = try NotesBundle.load(stagedURL)
                guard bundle.native == credentialsMode, bundle.otpOnly == otpMode else { throw NotesFailure.invalidTransport }
                notesBundle = bundle; notesDigest = digest
                text.stringValue = "已准备 \(bundle.source_count) 个来源的 \(bundle.items.count) 条关联资料。\n资料保存在 Apple「密码」的独立备注中，原账号和网站列在备注里。\n不会覆盖你现有的账号、密码、验证码或共享设置。\n\n点击下方按钮，在系统窗口选择「密码」接收。\n交接后仍须验收完整内容，再决定是否停用 1Password。"
                if credentialsMode { text.stringValue = "已准备 \(bundle.items.count) 条原生账号补齐资料。\n本批次只包含未匹配的明确账号；已有冲突项和验证码不在此批次。\nSSO 使用对应提供方账号，密码保持为空。\n完整资料仍由已验收的关联备注保留。\n\n点击下方按钮，在系统窗口选择「密码」接收。\n交接后将定向核对账号、密码和网站关联。" }
                if bundle.boundOTPCount > 0 { text.stringValue = "已准备 \(bundle.boundOTPCount) 条登录与验证码的组合资料。\n验证码和明确账号绑定在同一个条目，密码及网站随批次保留。\n不会后台点击、替换或执行导入。\n\n点击按钮后，由你在 Apple 系统窗口决定接收。\n已有条目是否合并、密码是否保留，仍须独立读回核对。" }
                if otpMode {
                    let synthetic = bundle.items.allSatisfy { $0.source_ids.allSatisfy {$0.hasPrefix("SYNTHETIC_OTP_TRIAL_")} && $0.totp?.username.hasSuffix("@example.invalid") == true && $0.urls!.allSatisfy { URL(string:$0)?.host?.hasSuffix(".invalid") == true } }
                    text.stringValue = "已准备 \(bundle.items.count) 条\(synthetic ? "虚构测试" : "来源关联")验证码。\n仅交接验证码配置、网站和关联备注，不发送密码字段。\n\(synthetic ? "本批次不读取 1Password，也不包含真实账号秘密。" : "接收应用如何合并验证码仍须验收。")\n\n点击下方按钮，在系统窗口选择「密码」接收。\n交接后将后台核对验证码及测试登录密码。\n若系统要求替换已有条目，请先停止。"
                }
            } catch {
                startupFailure = notesFailureReport(error,attemptStarted:false,exchangeAPIInvoked:false,guiLaunched:true)
                text.stringValue = startupFailure!["user_message"] as! String
            }
        }
        text.frame = NSRect(x:24,y:125,width:542,height:170); text.font = .systemFont(ofSize:14); body.addSubview(text)
        exportButton = NSButton(title:"开始交接 3 条测试资料…", target:self, action:#selector(beginExport)); exportButton.frame = NSRect(x:24,y:80,width:310,height:34); body.addSubview(exportButton)
        status = NSTextField(wrappingLabelWithString:"尚未交接。此组件不建立密码库。"); status.frame = NSRect(x:24,y:20,width:542,height:48); body.addSubview(status)
        if otpLoginDemoMode {
            exportButton.title = "交接一条虚构登录与验证码…"
            exportButton.isEnabled = otpLoginDigest != nil
            if let failure = startupFailure { status.stringValue = failure["user_message"] as! String }
        }
        if notesMode {
            exportButton.title = otpMode ? "将验证码交接给「密码」…" : credentialsMode ? "将原生账号交接给「密码」…" : "将关联资料交接给「密码」…"
            exportButton.isEnabled = notesBundle != nil && !FileManager.default.fileExists(atPath:journalURL.path)
            if FileManager.default.fileExists(atPath:journalURL.path) { status.stringValue = "此批次已有交接记录，须先核对结果；自动重复导入已阻止。" }
            else if let failure = startupFailure { status.stringValue = failure["user_message"] as! String }
        }
        if startupCheck {
            let report: [String:Any] = ["startup_initialized":true,
                "control_enabled":exportButton.isEnabled,"status_initialized":!status.stringValue.isEmpty,
                "control_title_exact":exportButton.title == (otpLoginDemoMode ? "交接一条虚构登录与验证码…" : "将原生账号交接给「密码」…"),
                "window_presented":window.isVisible,
                "application_activation_prohibited":NSApplication.shared.activationPolicy() == .prohibited,
                "exchange_api_invoked":false,"attempt_started":false]
            print(String(decoding:try! JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self))
            exit(0)
        }
        window.center(); window.makeKeyAndOrderFront(nil)
    }
    @objc func beginExport() {
        exportButton.isEnabled = false
        status.stringValue = "等待 Apple 系统交接…"
        Task { @MainActor in
            var attemptStarted = false
            var exchangeAPIInvoked = false
            do {
                if otpLoginDemoMode {
                    _ = try ExchangeOTPLoginDemo.preflight()
                    guard try ExchangeOTPLoginDemo.digest() == otpLoginDigest else { throw NotesFailure.invalidTransport }
                    try NotesBundle.beginAttempt(digest:otpLoginDigest!,directory:notesDirectory,native:true); attemptStarted = true
                }
                if notesMode {
                    let (fresh,digest) = try NotesBundle.load(stagedURL)
                    guard fresh == notesBundle && digest == notesDigest && fresh.native == credentialsMode && fresh.otpOnly == otpMode else { throw NotesFailure.invalidTransport }
                    try NotesBundle.beginAttempt(digest:digest,directory:notesDirectory,native:credentialsMode,otpOnly:otpMode); attemptStarted = true
                }
                let manager = ASCredentialExportManager(presentationAnchor:window)
                exportManager = manager
                exchangeAPIInvoked = true
                let options = try await manager.requestExport()
                let payload = otpLoginDemoMode ? ExchangeOTPLoginDemo.data(version:options.formatVersion) : notesMode ? notesBundle!.credentialData(version:options.formatVersion) : ExchangeDemo.data(version:options.formatVersion)
                try await manager.exportCredentials(payload)
                if otpLoginDemoMode {
                    try NotesBundle.finishAttempt(digest:otpLoginDigest!,phase:"api_completed_verification_pending",directory:notesDirectory,native:true)
                    status.stringValue = "系统交接已返回；这条虚构登录及验证码仍须后台验收。"
                    store(["export_api_completed":true,"otp_login_control_mode":true,"fixture_sha256":otpLoginDigest!,"test_record_count":1,"synthetic_only":true,"real_user_record_used":false,"native_apple_import_verified":false,"native_totp_import_verified":false])
                } else if notesMode {
                    try NotesBundle.finishAttempt(digest:notesDigest!,phase:"api_completed_verification_pending",directory:notesDirectory,native:credentialsMode,otpOnly:otpMode)
                    status.stringValue = "系统交接已返回；\(notesBundle!.items.count) 条关联资料仍须完整验收，才能停用 1Password。"
                    store(["export_api_completed":true,"notes_preservation_mode": !(credentialsMode || otpMode),"native_credentials_mode":credentialsMode,"otp_only_mode":otpMode,"otp_count":otpMode ? notesBundle!.items.count : notesBundle!.boundOTPCount,"bound_otp_count":notesBundle!.boundOTPCount,"note_count":notesBundle!.items.count,"source_count":notesBundle!.source_count,"credential_overwrites_verified":false,"native_apple_import_verified":false,"real_user_record_used": !notesBundle!.items.allSatisfy {$0.source_ids.allSatisfy {$0.hasPrefix("SYNTHETIC_OTP_TRIAL_") || $0.hasPrefix("SYNTHETIC_BOUND_OTP_")}}])
                } else {
                    status.stringValue = "系统交接已返回。尚未证明「密码」完整接收，请回传这 3 条测试资料验收。"
                    store(["export_api_completed":true,"native_apple_import_verified":false,"test_record_count":3,"real_user_record_used":false])
                }
            } catch {
                if otpLoginDemoMode && attemptStarted { try? NotesBundle.finishAttempt(digest:otpLoginDigest!,phase:"failed_verification_required",directory:notesDirectory,native:true) }
                if notesMode && attemptStarted { try? NotesBundle.finishAttempt(digest:notesDigest!,phase:"failed_verification_required",directory:notesDirectory,native:credentialsMode,otpOnly:otpMode) }
                var report = notesFailureReport(error,attemptStarted:attemptStarted,exchangeAPIInvoked:exchangeAPIInvoked,guiLaunched:true)
                status.stringValue = report["user_message"] as! String
                report["notes_preservation_mode"] = notesMode && !(credentialsMode || otpMode)
                report["native_credentials_mode"] = credentialsMode
                report["otp_only_mode"] = otpMode
                report["otp_login_control_mode"] = otpLoginDemoMode
                store(report)
            }
            exportButton.isEnabled = !(notesMode || otpLoginDemoMode)
        }
    }
    func application(_ application: NSApplication, continue activity: NSUserActivity, restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {
        guard activity.activityType == ASCredentialExchangeActivity, let token = activity.userInfo?[ASCredentialImportToken] as? UUID else { return false }
        Task { @MainActor in
            do {
                let received = try await ASCredentialImportManager().importCredentials(token:token)
                let bundle = try? NotesBundle.load(stagedURL).0
                let report = otpLoginDemoMode ? ExchangeOTPLoginDemo.inspect(received) : bundle?.inspect(received) ?? ExchangeDemo.inspect(received)
                store(report)
                status.stringValue = report["data_roundtrip_matches"] as? Bool == true ? "关联资料已全部精确读回；仍须确认回传来自 Apple「密码」，并验收原生账号能力。" : "回传资料存在缺失或变化，全库验收尚未完成。"
            } catch {
                let e = error as NSError
                store(["native_apple_import_verified":false,"error_domain":e.domain,"error_code":e.code])
                status.stringValue = "回传未完成（\(e.domain)，\(e.code)）。"
            }
        }
        return true
    }
    func store(_ report: [String:Any]) {
        do {
            let root = (notesMode || otpLoginDemoMode) ? notesDirectory : NotesBundle.root
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let path = root.appendingPathComponent("latest-result.json")
            let data = try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.prettyPrinted])
            try data.write(to:path,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)
        } catch { status.stringValue += " 本地验收报告无法保存。" }
    }
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--inspect-process",
   let pid = CommandLine.arguments[2] == "self" ? getpid() : Int32(CommandLine.arguments[2]), pid > 0 {
    let result = inspectProcess(pid)
    let data = try! JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
    print(String(decoding:data,as:UTF8.self)); exit(result["inspection_succeeded"] as? Bool == true ? 0 : 2)
} else if nativeArguments == ["--otp-login-demo-check"] || (nativeArguments.count == 2 && nativeArguments[0] == "--otp-login-demo-check") {
    do {
        let directory = nativeArguments.count == 2 ? URL(fileURLWithPath:nativeArguments[1],isDirectory:true) : ExchangeOTPLoginDemo.directory
        let report = try ExchangeOTPLoginDemo.preflight(directory:directory)
        print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self)); exit(0)
    } catch {
        let report = notesFailureReport(error,attemptStarted:false,exchangeAPIInvoked:false,guiLaunched:false)
        print(String(decoding:try! JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self)); exit(2)
    }
} else if CommandLine.arguments.dropFirst().elementsEqual(["--self-test"]) {
    do {
        let result = try ExchangeDemo.selfTest()
        let data = try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
        print(String(decoding:data,as:UTF8.self)); exit(result["passed"] as? Bool == true ? 0 : 2)
    } catch { print("{\"passed\":false,\"error\":\"codec_failed\"}"); exit(2) }
} else if (CommandLine.arguments.count == 2 || CommandLine.arguments.count == 3 || (CommandLine.arguments.count == 4 && nativeBatch != nil)) && ["--notes-check","--credentials-check","--otp-check"].contains(CommandLine.arguments[1]) {
    do {
        let native = CommandLine.arguments[1] == "--credentials-check"
        let otpOnly = CommandLine.arguments[1] == "--otp-check"
        let url = nativeBatch != nil ? NotesBundle.directory(batch:nativeBatch).appendingPathComponent(NotesBundle.transportName(native:native,otpOnly:otpOnly)) : CommandLine.arguments.count == 3 ? URL(fileURLWithPath:CommandLine.arguments[2]) : NotesBundle.stagedURL
        let report = try NotesBundle.preflight(url,native:native,otpOnly:otpOnly)
        print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self)); exit(0)
    } catch {
        let report = notesFailureReport(error,attemptStarted:false,exchangeAPIInvoked:false,guiLaunched:false)
        print(String(decoding:try! JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self)); exit(2)
    }
} else if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--notes-journal-self-test" {
    do {
        let report = try NotesBundle.journalSelfTest(directory:URL(fileURLWithPath:CommandLine.arguments[2]))
        print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self))
        exit(report["duplicate_attempt_blocked"] as? Bool == true ? 0 : 2)
    } catch { print("{\"error\":\"notes_journal_invalid\"}"); exit(2) }
} else if CommandLine.arguments.count == 3 && ["--validate-notes","--validate-credentials","--validate-otp"].contains(CommandLine.arguments[1]) {
    do {
        let (bundle,_) = try NotesBundle.load(URL(fileURLWithPath:CommandLine.arguments[2]))
        guard bundle.native == (CommandLine.arguments[1] == "--validate-credentials"), bundle.otpOnly == (CommandLine.arguments[1] == "--validate-otp") else { throw NotesFailure.invalidTransport }
        let report = try bundle.validationReport()
        print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self))
        exit(report["codec_exact"] as? Bool == true ? 0 : 2)
    } catch { print("{\"error\":\"notes_transport_invalid\",\"native_apple_import_verified\":false}"); exit(2) }
} else if CommandLine.arguments.count != 1 && nativeArguments != ["--notes-import"] && nativeArguments != ["--otp-login-demo"] && nativeArguments != ["--otp-login-demo-startup-check"] && !(nativeBatch != nil && ["--notes-import","--credentials-import","--credentials-startup-check","--otp-import"].contains(nativeArguments[0])) {
    print("{\"error\":\"only_synthetic_trial_supported\"}"); exit(2)
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = ExchangeApp(); app.delegate = delegate
        app.setActivationPolicy(delegate.startupCheck ? .prohibited : .regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
