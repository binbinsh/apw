// Optional official API trial for apw. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AuthenticationServices
@objc(APWExchangeProvider) final class APWExchangeProvider: ASCredentialProviderViewController {
    override func loadView() {
        let view = NSView(frame:NSRect(x:0,y:0,width:420,height:100))
        let label = NSTextField(wrappingLabelWithString:"此 apw 组件只用于 3 条合成资料的官方迁移测试。")
        label.frame = NSRect(x:16,y:20,width:388,height:64); view.addSubview(label); self.view = view
    }
}
