// SPDX-License-Identifier: GPL-3.0-only
// Own-process fixture only. No Apple/other app AX access, activation or global input.
import AppKit
import SwiftUI
import ApplicationServices
import Foundation
import Darwin

let originalText="APW_FIXTURE_ORIGINAL_V1"
let replacementText=originalText+"\n中文 🙂 e\u{301}\nAPW_FIXTURE_INPUT_V1"
let args=Array(CommandLine.arguments.dropFirst())
guard args==["--self-owned-input-fixture"] else{exit(2)}
umask(0o077)
let foregroundBefore=NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
let app=NSApplication.shared
_ = app.setActivationPolicy(.prohibited)
var result:[String:Any]=["fixture_only":true,"fixture_pid":getpid(),"foreground_before":foregroundBefore,"app_activated":false,
 "global_input_events_sent":0,"input_events_sent":0,"pid_targeted":0,"clipboard_used":false,"other_app_ax_accessed":false,
 "window_became_key":false,"internal_first_responder_exact":false,"selection_verified":false,
 "model_committed":false,"persisted_readback_exact":false,"binding_change_count":0]
let stateDirectory=FileManager.default.temporaryDirectory.appendingPathComponent("apw-own-input-"+UUID().uuidString,isDirectory:true)
try FileManager.default.createDirectory(at:stateDirectory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
let stateURL=stateDirectory.appendingPathComponent("model.json")
var window:NSWindow?
@MainActor func ownerPreserved()->Bool {
 foregroundBefore>0 && foregroundBefore != getpid() && NSWorkspace.shared.frontmostApplication?.processIdentifier==foregroundBefore && window?.isKeyWindow != true && window?.isMainWindow != true
}
@MainActor func finish(_ hold:String?=nil)->Never {
 let current=NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
 result["foreground_after"]=current;result["owner_preserved"]=ownerPreserved()
 result["window_became_key"]=window?.isKeyWindow==true || window?.isMainWindow==true
 if let hold {result["held"]=hold}
 window?.close()
 try? FileManager.default.removeItem(at:stateDirectory)
 let bytes=try! JSONSerialization.data(withJSONObject:result,options:.sortedKeys)
 print(String(data:bytes,encoding:.utf8)!);fflush(stdout)
 exit(hold==nil && result["model_committed"] as? Bool==true && result["owner_preserved"] as? Bool==true ? 0:2)
}
MainActor.assumeIsolated {guard ownerPreserved() else{finish("fixture_initial_owner_unavailable_or_changed")}}
@MainActor final class Model:ObservableObject {
 @Published var text=originalText
 var changes=0
 func assign(_ value:String) {
  guard ownerPreserved() else{finish("fixture_owner_changed")}
  if text != value {text=value;changes+=1}
  let data=try! JSONSerialization.data(withJSONObject:["model":text,"changes":changes],options:.sortedKeys)
  try! data.write(to:stateURL,options:.atomic);chmod(stateURL.path,0o600)
 }
}
struct Content:View {
 @ObservedObject var model:Model
 var body:some View {
  TextField("Synthetic notes",text:Binding(get:{model.text},set:{model.assign($0)}),axis:.vertical)
   .textFieldStyle(.roundedBorder).accessibilityIdentifier("OwnedFixtureNotesField")
   .padding(20).frame(width:460,height:160)
 }
}
let model=MainActor.assumeIsolated {Model()}
window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:460,height:160),styleMask:[.titled],backing:.buffered,defer:false)
window!.isReleasedWhenClosed=false;window!.title="APW_OWN_INPUT_FIXTURE"
window!.contentView=NSHostingView(rootView:Content(model:model))
window!.orderBack(nil)
MainActor.assumeIsolated {guard ownerPreserved() else{finish("fixture_window_changed_owner")}}
var controls:[NSTextField]=[]
@MainActor func collect(_ view:NSView) {
 if let field=view as? NSTextField,field.isEditable,field.stringValue==originalText {controls.append(field)}
 for child in view.subviews {collect(child)}
}
@MainActor func setup() {
 guard ownerPreserved() else{finish("fixture_owner_changed")}
 controls=[];if let content=window?.contentView {collect(content)}
 guard controls.count==1,let window else{finish("fixture_unique_control_unavailable")}
 let field=controls[0]
 guard window.makeFirstResponder(field),ownerPreserved(),let editor=field.currentEditor() as? NSTextView,
  window.firstResponder===editor,editor.window===window,editor.isEditable,editor.string==originalText else{finish("fixture_internal_first_responder_unavailable")}
 result["internal_first_responder_exact"]=true
 editor.setSelectedRange(NSRange(location:0,length:originalText.utf16.count))
 let selection=editor.selectedRange()
 guard ownerPreserved(),selection.location==0,selection.length==originalText.utf16.count else{finish("fixture_full_selection_unverified")}
 result["selection_verified"]=true
 guard CGPreflightPostEventAccess() else{finish("fixture_event_post_access_absent")}
 guard CGEventSource.flagsState(.hidSystemState).rawValue==0 else{finish("fixture_physical_modifiers_present")}
 guard let down=CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:true),let up=CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:false) else{finish("fixture_event_creation_failed")}
 let units=Array(replacementText.utf16)
 units.withUnsafeBufferPointer {
  down.keyboardSetUnicodeString(stringLength:$0.count,unicodeString:$0.baseAddress!)
  up.keyboardSetUnicodeString(stringLength:$0.count,unicodeString:$0.baseAddress!)
 }
 down.flags=[];up.flags=[]
 guard ownerPreserved(),window.firstResponder===editor,field.currentEditor()===editor,editor.selectedRange()==selection else{finish("fixture_pre_event_scope_changed")}
 // The PID is our own getpid, not an argument or discovered third party.
 down.postToPid(getpid());result["input_events_sent"]=1;result["pid_targeted"]=getpid()
 guard ownerPreserved(),window.firstResponder===editor else{finish("fixture_between_events_scope_changed")}
 up.postToPid(getpid());result["input_events_sent"]=2
 DispatchQueue.main.asyncAfter(deadline:.now()+0.6) {
  guard ownerPreserved() else{finish("fixture_after_event_owner_changed")}
  result["binding_change_count"]=model.changes;result["model_committed"]=model.text==replacementText
  let state=(try? Data(contentsOf:stateURL)).flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}
  result["persisted_readback_exact"]=state?["model"] as? String==replacementText && state?["changes"] as? Int==model.changes
  if model.text != replacementText {finish("fixture_nonkey_dispatch_did_not_commit")}
  finish()
 }
}
DispatchQueue.main.asyncAfter(deadline:.now()+0.2){setup()}
let safety=Timer.scheduledTimer(withTimeInterval:0.05,repeats:true){_ in MainActor.assumeIsolated {if !ownerPreserved(){finish("fixture_owner_changed")}}}
DispatchQueue.main.asyncAfter(deadline:.now()+5){finish("fixture_deadline")}
app.run()
_ = safety
