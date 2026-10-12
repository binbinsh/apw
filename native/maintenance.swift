// SPDX-License-Identifier: GPL-3.0-only
// Native backend for apw item/batch maintenance. Never activates apps.
import AppKit
import ApplicationServices
import Foundation
import Security
import CryptoKit

struct CandidateObservation: Codable {
 let unique, identity_exact, fields_present: Bool
 let notes, username, password: String
 let websites_known: Bool; let websites: [String]
 let otp_absent, passkey_absent: Bool; let sharing: String
}
struct RetainerObservation: Codable {
 let unique, identity_exact, fields_present: Bool; let notes, sharing: String
}
struct Proof: Codable {
 let expected_note: String; let source_ids: [String]; let expected_retainer_note: String
 let candidate: CandidateObservation; let retainer: RetainerObservation
 let foreground, no_user_editor, within_deadline, candidate_unchanged: Bool
 let delete_dialog_exact, recoverable_delete, active_absence, retainer_after_exact: Bool
}
struct BackgroundOwnerObservation:Decodable {
 let original_foreground,current_foreground,passwords_pid:pid_t
 let keyboard_pid:pid_t?
 let deadline_valid,input_events,focus_setter,selected_text_setter,app_activation:Bool
}
func permitsBackgroundOwner(_ o:BackgroundOwnerObservation)->Bool {
 o.original_foreground>0 && o.passwords_pid>0 && o.original_foreground != o.passwords_pid &&
 o.current_foreground>0 && o.current_foreground != o.passwords_pid && o.deadline_valid &&
 (o.keyboard_pid==nil || (o.keyboard_pid!>0 && o.keyboard_pid != o.passwords_pid)) &&
 !o.input_events && !o.focus_setter && !o.selected_text_setter && !o.app_activation
}
func permits(_ p: Proof)->Bool {
 let c=p.candidate,r=p.retainer
 return p.foreground && p.no_user_editor && p.within_deadline && p.candidate_unchanged &&
  c.unique && c.identity_exact && c.fields_present && c.notes==p.expected_note &&
  !p.expected_note.isEmpty && !p.source_ids.isEmpty && p.source_ids.allSatisfy{c.notes.contains($0)} &&
  c.username.isEmpty && c.password.isEmpty && c.websites_known && c.websites.isEmpty && c.otp_absent && c.passkey_absent && c.sharing=="unshared" &&
  r.unique && r.identity_exact && r.fields_present && r.notes==p.expected_retainer_note &&
  r.notes.contains(p.expected_note) && p.source_ids.allSatisfy{r.notes.contains($0)} && r.sharing=="unshared"
}
struct Target: Codable { let title, native_title, username, notes: String; let urls: [String] }
struct Widget:Decodable {let role,identifier,value:String}
func additionalEditableData(_ role:String,_ id:String,_ value:String)->Bool {
 ["AXTextField","AXComboBox"].contains(role) && !["TitleField","UserNameField","PasswordField","NotesField","VerificationCodeField"].contains(id) && !value.isEmpty
}
struct Item: Codable {let id,title,expected_note: String;let source_ids:[String];let retained:Target}
struct Request: Codable {
 let format, basis_path, basis_sha256, capture_path, capture_sha256, candidates_path, candidates_sha256: String
 let items:[Item]
}
struct Blocked: Decodable {
 struct Record:Decodable {let id,title,expected_note_sha256:String;let source_ids:[String]}
 let items:[Record];let csv_sha256,basis_sha256:String;let capture_rows_are_native_ids:Bool
}
func digest(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
func privateData(_ path:String)->Data? {
 var st=stat();guard lstat(path,&st)==0,(st.st_mode&S_IFMT)==S_IFREG,st.st_uid==getuid(),st.st_mode&0o077==0,st.st_size<=64*1024*1024 else{return nil}
 let fd=open(path,O_RDONLY|O_NOFOLLOW);guard fd>=0 else{return nil};defer{close(fd)}
 var actual=stat();guard fstat(fd,&actual)==0,actual.st_ino==st.st_ino,actual.st_dev==st.st_dev else{return nil}
 let h=FileHandle(fileDescriptor:fd,closeOnDealloc:false)
 return try? h.readToEnd()
}
let args=Array(CommandLine.arguments.dropFirst())
// A command-line observer has no reason to become an activatable application.
let application=NSApplication.shared
_ = application.setActivationPolicy(.prohibited)
var report:[String:Any] = ["live_deletions":0,"credential_writes":0,"app_activated":false,"input_events_sent":false,
 "exports":0,"imports":0,"source_values_logged":false,"permanent_deletions":0,"safe_to_remove_1password":false]
// Apple documents that only the system-wide element changes the process default.
let nativeTimeoutSetup=AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(),0.25)
report["native_timeout_setup_code"]=nativeTimeoutSetup.rawValue
report["native_global_timeout_seconds"]=0.25
report["native_timeout_scope"]="helper_process"
var nativeObservationIncomplete=false
struct NativeErrorObservation:Decodable {let code:Int32;let required:Bool}
func nativeReadErrorRefuses(_ code:AXError,required:Bool)->Bool {
 [AXError.cannotComplete,AXError.invalidUIElement,AXError.illegalArgument].contains(code) || (required && code != .success)
}
func observeNativeError(_ code:AXError,required:Bool=false) {
 if nativeReadErrorRefuses(code,required:required) {
  nativeObservationIncomplete=true
  var counts=report["native_incomplete_error_counts"] as? [String:Int] ?? [:]
  counts[String(code.rawValue),default:0]+=1;report["native_incomplete_error_counts"]=counts
 }
}
func completeDiscovery<T>(_ operation:()->T)->T? {
 let prior=nativeObservationIncomplete
 nativeObservationIncomplete=false
 let result=operation(),complete = !nativeObservationIncomplete
 nativeObservationIncomplete=prior
 if !complete {report["discarded_incomplete_discovery_scans"]=(report["discarded_incomplete_discovery_scans"] as? Int ?? 0)+1}
 return complete ? result:nil
}
struct DiscoveryScopeObservation:Decodable {let prior_incomplete:Bool;let codes:[Int32]}
var deadline=Date(timeIntervalSinceNow:90)
func pause(_ seconds:TimeInterval) {RunLoop.current.run(until:Date(timeIntervalSinceNow:seconds))}
var appPID:pid_t=0
var backgroundOwnerPID:pid_t?
var refreshActiveSearchModel=false
var scanActiveList=true
var indexedLabels:[[String]]?
var backgroundUnsafeFocusObserved=false
func attr(_ n:AXUIElement,_ k:String)->CFTypeRef? {
 guard Date()<deadline else{return nil};var v:CFTypeRef?
 let code=AXUIElementCopyAttributeValue(n,k as CFString,&v);observeNativeError(code,required:k==kAXRoleAttribute)
 return code == .success ? v:nil
}
func text(_ n:AXUIElement,_ k:String)->String {attr(n,k) as? String ?? ""}
func nodes(_ root:AXUIElement,prune:Bool=true)->[AXUIElement] {
 var out:[AXUIElement]=[];var seen=Set<UInt>()
 func walk(_ n:AXUIElement,_ depth:Int){guard depth<24,out.count<6000,Date()<deadline,seen.insert(CFHash(n)).inserted else{return};let r=text(n,kAXRoleAttribute);guard !["AXMenuBar","AXMenu","AXMenuItem"].contains(r) else{return};out.append(n);if prune && ["AXOutline","AXTable"].contains(r){return};for c in attr(n,kAXChildrenAttribute) as? [AXUIElement] ?? [] {walk(c,depth+1)}}
 walk(root,0);return out
}
func values(_ ns:[AXUIElement])->[String] {ns.flatMap{n in [kAXTitleAttribute,kAXDescriptionAttribute,kAXValueAttribute].compactMap{attr(n,$0) as? String}}}
func rowValues(_ row:AXUIElement)->[String] {
 var out:[String]=[],seen=Set<UInt>()
 let names=[kAXRoleAttribute,kAXTitleAttribute,kAXDescriptionAttribute,kAXValueAttribute,kAXChildrenAttribute] as CFArray
 func walk(_ n:AXUIElement,_ depth:Int) {
  guard depth<12,seen.count<100,Date()<deadline,seen.insert(CFHash(n)).inserted else{return}
  var values:CFArray?
  let code=AXUIElementCopyMultipleAttributeValues(n,names,[],&values);observeNativeError(code,required:true)
  guard code == .success,let v=values as? [Any],v.count==5,v[0] is String else{nativeObservationIncomplete=true;return}
  out.append(contentsOf:v[1...3].compactMap{$0 as? String})
  for child in v[4] as? [AXUIElement] ?? [] {walk(child,depth+1)}
 }
 walk(row,0);return out
}
func focusPID()->pid_t? {
 _=NSApplication.shared;var v:CFTypeRef?;guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(),kAXFocusedApplicationAttribute as CFString,&v) == .success,let v,CFGetTypeID(v)==AXUIElementGetTypeID() else{return nil};var pid:pid_t=0;return AXUIElementGetPid(unsafeBitCast(v,to:AXUIElement.self),&pid) == .success ? pid:nil
}
func safeBackgroundOwner(_ original:pid_t)->Bool {
 let keyboard=focusPID()
 report["background_keyboard_owner_available"]=keyboard != nil
 let passwords=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Passwords").first?.processIdentifier ?? 0
 return permitsBackgroundOwner(BackgroundOwnerObservation(original_foreground:original,current_foreground:NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0,passwords_pid:passwords,keyboard_pid:keyboard,deadline_valid:Date()<deadline,input_events:false,focus_setter:false,selected_text_setter:false,app_activation:false))
}
func front()->Bool {
 let expected=backgroundOwnerPID ?? appPID
 let foreground=NSWorkspace.shared.frontmostApplication?.processIdentifier,keyboard=focusPID()
 let addressedBackground=backgroundOwnerPID != nil
 if addressedBackground {
  report["background_keyboard_owner_available"]=keyboard != nil
  if foreground != expected {report["background_user_app_switch_observed"]=true}
  if foreground==appPID || keyboard==appPID {backgroundUnsafeFocusObserved=true}
 }
 if addressedBackground {report["keyboard_focus_outside_passwords"]=keyboard==nil || keyboard != appPID}
 let good=addressedBackground ? permitsBackgroundOwner(BackgroundOwnerObservation(original_foreground:expected,current_foreground:foreground ?? 0,passwords_pid:appPID,keyboard_pid:keyboard,deadline_valid:Date()<deadline,input_events:false,focus_setter:false,selected_text_setter:false,app_activation:false)) : (Date()<deadline && appPID != 0 && foreground==expected && keyboard==expected)
 if !good,appPID != 0 {
  report["owner_guard_observation"]=["original_frontmost_preserved":foreground==expected,"original_keyboard_owner_preserved":keyboard==expected,
   "passwords_frontmost":foreground==appPID,"passwords_keyboard_owner":keyboard==appPID,"deadline_valid":Date()<deadline]
 }
 return good
}
func finishBackgroundLease() {
 let good=front()
 report["original_foreground_preserved"]=NSWorkspace.shared.frontmostApplication?.processIdentifier==backgroundOwnerPID
 report["background_non_passwords_foreground_preserved"]=good && !backgroundUnsafeFocusObserved
 report["background_passwords_focus_observed"]=backgroundUnsafeFocusObserved
 backgroundOwnerPID=nil
}
func scriptOwnerGuard(_ expression:String)->String {
 if backgroundOwnerPID != nil {return "if (\(expression)) is less than 1 or (\(expression)) is \(appPID) then error \"owner_changed\""}
 return "if (\(expression)) is not \(appPID) then error \"owner_changed\""
}
func owned(_ n:AXUIElement)->Bool {var pid:pid_t=0;return front() && AXUIElementGetPid(n,&pid) == .success && pid==appPID}
func set(_ n:AXUIElement,_ k:String,_ v:CFTypeRef)->Bool {
 let notesSelection=[kAXSelectedTextAttribute,kAXSelectedTextRangeAttribute].contains(k) && text(n,kAXIdentifierAttribute)=="NotesField" && text(n,kAXRoleAttribute)=="AXTextArea"
 guard k != kAXFocusedAttribute,!(backgroundOwnerPID != nil && [kAXSelectedTextAttribute,kAXSelectedTextRangeAttribute].contains(k) && !notesSelection),owned(n) else{report["ui_set_foreground_gate_refused"]=true;return false}
 let result=AXUIElementSetAttributeValue(n,k as CFString,v)
 if result != .success {report["ui_set_attribute"]=k;report["ui_set_error_code"]=result.rawValue}
 return result == .success
}
func press(_ n:AXUIElement)->Bool {
 guard owned(n) else{report["ui_press_foreground_gate_refused"]=true;return false}
 let result=AXUIElementPerformAction(n,kAXPressAction as CFString)
 if result != .success {report["ui_press_error_code"]=result.rawValue}
 return result == .success
}
// Derive a current UI-element address without walking the account outline.
func confirmationEditorAddress(_ root:AXUIElement)->String? {
 let all=nodes(root),windows=all.filter{text($0,kAXSubroleAttribute)=="AXStandardWindow"}
 let titles=all.filter{text($0,kAXIdentifierAttribute)=="TitleField"}
 guard front(),windows.count==1,titles.count==1 else{return nil}
 let window=windows[0];var current=titles[0];var editor:AXUIElement?
 for _ in 0..<16 {
  guard let parent=attr(current,kAXParentAttribute),CFGetTypeID(parent)==AXUIElementGetTypeID() else{return nil}
  current=unsafeBitCast(parent,to:AXUIElement.self);let ns=nodes(current)
  if ns.contains(where:{["AXOutline","AXTable","AXToolbar","AXSheet","AXWindow"].contains(text($0,kAXRoleAttribute)) || text($0,kAXIdentifierAttribute)=="AccountListView"}) {return nil}
  if ["TitleField","UserNameField","PasswordField","NotesField"].allSatisfy({id in ns.filter{text($0,kAXIdentifierAttribute)==id}.count==1}) {editor=current;break}
 }
 guard let editor else{return nil}
 let editorRole=text(editor,kAXRoleAttribute)
 guard ["AXGroup","AXScrollArea","AXSplitGroup"].contains(editorRole) else{return nil}
 report["confirmation_native_editor_role"]=editorRole
 current=editor;var indexes:[Int]=[]
 for _ in 0..<16 {
  if CFEqual(current,window) {
   report["confirmation_editor_path_depth"]=indexes.count
   report["confirmation_account_list_enumerated"]=false
   var expression="w"
   for index in indexes {expression="UI element \(index) of (\(expression))"}
   return expression
  }
  guard let parent=attr(current,kAXParentAttribute),CFGetTypeID(parent)==AXUIElementGetTypeID() else{return nil}
  let p=unsafeBitCast(parent,to:AXUIElement.self),role=text(p,kAXRoleAttribute)
  guard !["AXOutline","AXTable","AXSheet"].contains(role),let children=attr(p,kAXChildrenAttribute) as? [AXUIElement] else{return nil}
  let matches=children.indices.filter{CFEqual(children[$0],current)}
  guard matches.count==1 else{return nil}
  indexes.insert(matches[0]+1,at:0);current=p
 }
 return nil
}
func confirmRecoverable(_ i:Item,probe:Bool=false)->Bool {
 guard front() else{return false}
 let title=Data(i.title.utf8).base64EncodedString(),note=Data(i.expected_note.utf8).base64EncodedString()
 let address=probe ? "w":confirmationEditorAddress(AXUIElementCreateApplication(appPID))
 guard let address else{report["confirmation_bridge_failure"]="editor_address_unavailable";return false}
 let editorRole=probe ? "AXGroup":(report["confirmation_native_editor_role"] as? String ?? "")
 let source="""
 use framework "Foundation"
 use scripting additions
 on decode64(encoded)
  set bytes to current application's NSData's alloc()'s initWithBase64EncodedString:encoded options:0
  return (current application's NSString's alloc()'s initWithData:bytes encoding:4) as text
 end decode64
 set expectedTitle to my decode64("\(title)")
 set expectedNote to my decode64("\(note)")
 tell application "System Events"
  \(scriptOwnerGuard("unix id of first application process whose frontmost is true"))
  tell process "Passwords"
   if unix id is not \(appPID) then error "process_changed"
   set apwTitleFields to {}
   set apwNoteFields to {}
   set apwUserFields to {}
   set apwPasswordFields to {}
   if \(probe ? "true":"false") then
    if (count apwTitleFields) is not 0 or (count apwNoteFields) is not 0 or (count apwUserFields) is not 0 or (count apwPasswordFields) is not 0 then error "synthetic_collections_changed"
    return "synthetic_variable_probe_passed"
   end if
   set ws to windows whose subrole is "AXStandardWindow"
   if (count ws) is not 1 then error "window_changed"
   set w to item 1 of ws
   if (count sheets of w) is not 1 then error "sheet_changed"
   set apwEditor to \(address)
   if (value of attribute "AXRole" of apwEditor) is not "\(editorRole)" then error "editor_address_changed"
   set es to entire contents of apwEditor
   repeat with el in es
    try
     set apwFieldIdentifier to value of attribute "AXIdentifier" of el
     if apwFieldIdentifier is "TitleField" then set end of apwTitleFields to contents of el
     if apwFieldIdentifier is "NotesField" then set end of apwNoteFields to contents of el
     if apwFieldIdentifier is "UserNameField" then set end of apwUserFields to contents of el
     if apwFieldIdentifier is "PasswordField" then set end of apwPasswordFields to contents of el
    end try
   end repeat
   if (count apwTitleFields) is not 1 or (count apwNoteFields) is not 1 or (count apwUserFields) is not 1 or (count apwPasswordFields) is not 1 then error "fields_ambiguous"
   if (value of item 1 of apwTitleFields as text) is not expectedTitle or (value of item 1 of apwNoteFields as text) is not expectedNote then error "identity_changed"
   if (value of item 1 of apwUserFields as text) is not "" or (value of item 1 of apwPasswordFields as text) is not "" then error "credential_changed"
   set s to sheet 1 of w
   set bs to {}
   set sheetElements to entire contents of s
   repeat with el in sheetElements
    try
     if (value of attribute "AXRole" of el) is "AXButton" then
      set caption to description of el as text
      if caption is "删除密码" or caption is "Delete Password" then set end of bs to contents of el
     end if
    end try
   end repeat
   if (count bs) is not 1 then error "ordinary_confirmation_unavailable"
   tell application "System Events" to set apwConfirmOwner to unix id of first application process whose frontmost is true
   \(scriptOwnerGuard("apwConfirmOwner"))
   if unix id is not \(appPID) then error "process_changed"
   if (count sheets of w) is not 1 then error "sheet_changed"
   click item 1 of bs
  end tell
 end tell
 return "acknowledged"
 """
 let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/osascript");process.arguments=["-"]
 let input=Pipe(),output=Pipe(),error=Pipe();process.standardInput=input;process.standardOutput=output;process.standardError=error
 do{try process.run();input.fileHandleForWriting.write(Data(source.utf8));try input.fileHandleForWriting.close()}catch{return false}
 let until=Date(timeIntervalSinceNow:10)
 while process.isRunning,Date()<until{pause(0.02)}
 if process.isRunning{process.terminate();report["confirmation_bridge_timed_out"]=true;return false}
 report["confirmation_bridge_exit_code"]=process.terminationStatus
 let diagnostic=String(data:error.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8) ?? ""
 report["confirmation_bridge_failure"]=["owner_changed","process_changed","window_changed","sheet_changed","fields_ambiguous","identity_changed","credential_changed","editor_address_changed","ordinary_confirmation_unavailable"].first{diagnostic.contains($0)} ?? (process.terminationStatus==0 ? "none":"unclassified_system_events_error")
 if let expression=try? NSRegularExpression(pattern:"\\((-?[0-9]+)\\)"),let match=expression.matches(in:diagnostic,range:NSRange(diagnostic.startIndex...,in:diagnostic)).last,let range=Range(match.range(at:1),in:diagnostic) {report["confirmation_bridge_system_error_code"]=Int(diagnostic[range])}
 let response=String(data:output.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines)
 return process.terminationStatus==0 && response==(probe ? "synthetic_variable_probe_passed":"acknowledged") && front()
}
func inSearchField(_ node:AXUIElement)->Bool {
 var current=node
 for _ in 0..<12 {
  if text(current,kAXSubroleAttribute)=="AXSearchField" {return true}
  guard let parent=attr(current,kAXParentAttribute),CFGetTypeID(parent)==AXUIElementGetTypeID() else{return false}
  current=unsafeBitCast(parent,to:AXUIElement.self)
 }
 return false
}
func button(_ ns:[AXUIElement],_ names:[String])->AXUIElement? {let b=ns.filter{text($0,kAXRoleAttribute)=="AXButton" && !inSearchField($0) && (names.contains(text($0,kAXTitleAttribute)) || names.contains(text($0,kAXDescriptionAttribute)))};return b.count==1 ? b[0]:nil}
func selectionDiagnostics(_ root:AXUIElement)->[String:Any] {
 let all=nodes(root),names=["编辑","Edit","编辑密码","Edit Password","编辑备注","Edit Note"]
 let labelled=all.filter{values([$0]).contains(where:{names.contains($0)})}
 let buttons=labelled.filter{text($0,kAXRoleAttribute)=="AXButton" && !inSearchField($0)}
 let lists=all.filter{text($0,kAXIdentifierAttribute)=="AccountListView"}
 var result:[String:Any]=["edit_label_roles":labelled.map{text($0,kAXRoleAttribute)},"edit_button_count":buttons.count,
  "standard_window_count":all.filter{text($0,kAXSubroleAttribute)=="AXStandardWindow"}.count,
  "sheet_count":all.filter{text($0,kAXRoleAttribute)=="AXSheet"}.count,
  "editor_fields_present":["TitleField","UserNameField","PasswordField","NotesField"].allSatisfy{id in all.contains{text($0,kAXIdentifierAttribute)==id}},
  "foreground_matches":front()]
 if lists.count==1 {
  result["selected_row_count"]=(attr(lists[0],kAXSelectedRowsAttribute) as? [AXUIElement])?.count ?? -1
  var writable=DarwinBoolean(false)
  result["list_selection_settable_query"]=AXUIElementIsAttributeSettable(lists[0],kAXSelectedRowsAttribute as CFString,&writable).rawValue
  result["list_selection_settable"]=writable.boolValue
 }
 return result
}
func context(_ root:AXUIElement)->(AXUIElement,AXUIElement)? {
 let all=nodes(root);guard front(),!all.contains(where:{text($0,kAXRoleAttribute)=="AXSheet"}),!(button(all,["保存","Save","完成","Done"]) != nil && button(all,["取消","Cancel"]) != nil) else{return nil}
 let f=all.filter{text($0,kAXRoleAttribute)=="AXToolbar"}.flatMap{nodes($0)}.filter{text($0,kAXRoleAttribute)=="AXTextField" && text($0,kAXSubroleAttribute)=="AXSearchField"}
 let lists=all.filter{["AXOutline","AXTable"].contains(text($0,kAXRoleAttribute)) && text($0,kAXIdentifierAttribute)=="AccountListView"}
 return f.count==1 && lists.count==1 ? (f[0],lists[0]):nil
}
func query(_ previous:AXUIElement,_ q:String)->Bool { context(AXUIElementCreateApplication(appPID)).map { text($0.0,kAXValueAttribute).isEmpty } ?? false }
func fields(_ ns:[AXUIElement])->[String:String] {
 var result:[String:String]=[:]
 for id in ["TitleField","UserNameField","PasswordField","NotesField","WebsiteField","VerificationCodeField"] {
  let matches=ns.filter{text($0,kAXIdentifierAttribute)==id}
  if matches.count==1,let v=attr(matches[0],kAXValueAttribute) as? String {result[id]=v}
 }
 return result
}
func formNodes(_ ns:[AXUIElement])->[AXUIElement] {
 let titles=ns.filter{text($0,kAXIdentifierAttribute)=="TitleField"}
 guard titles.count==1 else{return []};var current=titles[0]
 for _ in 0..<16 {
  guard let parent=attr(current,kAXParentAttribute),CFGetTypeID(parent)==AXUIElementGetTypeID() else{return []}
  current=unsafeBitCast(parent,to:AXUIElement.self);let form=nodes(current)
  if form.contains(where:{text($0,kAXRoleAttribute)=="AXToolbar" || text($0,kAXIdentifierAttribute)=="AccountListView"}) {return []}
  let ids=Set(form.map{text($0,kAXIdentifierAttribute)})
  if ["NotesField","UserNameField","WebsiteField"].allSatisfy({ids.contains($0)}) {return form}
 }
 return []
}
func sharing(_ ns:[AXUIElement])->String {
 let popup=ns.filter{text($0,kAXRoleAttribute)=="AXPopUpButton"}
 let found=popup.filter{values([$0]).contains(where:{["未共享","Not Shared"].contains($0)})}
 return found.count==1 ? "unshared":"unknown"
}
func host(_ value:String)->String {URLComponents(string:value.contains("://") ? value:"https://"+value)?.host?.lowercased() ?? ""}
func sectionLabel(_ value:String)->String {value.trimmingCharacters(in:CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn:":：\u{200e}\u{200f}")))}
func websites(_ editor:[AXUIElement])->(Bool,[String]) {
 let inputs=editor.filter{text($0,kAXIdentifierAttribute)=="WebsiteField"}
 guard inputs.count==1,let direct=attr(inputs[0],kAXValueAttribute) as? String else{return (false,[])}
 let role=text(inputs[0],kAXRoleAttribute)
 // This identifier is used both by a section label and by an existing website.
 // AXStaticText alone does not distinguish those two cases.
 guard ["AXStaticText","AXTextField","AXComboBox"].contains(role) else{return (false,[])}
 let section=role=="AXStaticText" && ["网站","website","websites"].contains(sectionLabel(direct).lowercased())
 let explicitNone=role=="AXStaticText" && ["无网站","no website","no websites"].contains(sectionLabel(direct).lowercased())
 if role=="AXStaticText",!section,!explicitNone,(direct.isEmpty || host(direct).isEmpty || direct.contains(where:{$0.isWhitespace})) {return (false,[])}
 var found=section || explicitNone || direct.isEmpty ? []:[direct];var current=inputs[0]
 for _ in 0..<12 {
  guard let parent=attr(current,kAXParentAttribute),CFGetTypeID(parent)==AXUIElementGetTypeID() else{break}
  current=unsafeBitCast(parent,to:AXUIElement.self);let form=nodes(current)
  if form.contains(where:{text($0,kAXRoleAttribute)=="AXToolbar" || text($0,kAXIdentifierAttribute)=="AccountListView"}) {break}
  // Existing Website links are siblings of the empty Add Website field.
  func scan(_ n:AXUIElement,_ depth:Int) {
   guard depth<16,Date()<deadline else{return};let id=text(n,kAXIdentifierAttribute),role=text(n,kAXRoleAttribute)
   guard !["TitleField","UserNameField","PasswordField","NotesField","VerificationCodeField","WebsiteField"].contains(id),!["AXToolbar","AXOutline","AXTable"].contains(role) else{return}
   if let value=attr(n,kAXValueAttribute) as? String,additionalEditableData(role,id,value) {found.append(value)}
   if let u=attr(n,kAXURLAttribute) as? URL {found.append(u.absoluteString)}
   if ["AXStaticText","AXLink","AXButton","AXTextField","AXComboBox"].contains(role) {for s in values([n]) where (s.contains(".") || s.contains("://") || s=="localhost") && !s.contains(where:{$0.isWhitespace}) && !s.contains("@") && !host(s).isEmpty {found.append(s)}}
   for child in attr(n,kAXChildrenAttribute) as? [AXUIElement] ?? [] {scan(child,depth+1)}
  }
  scan(current,0)
  if form.contains(where:{text($0,kAXIdentifierAttribute)=="TitleField"}) {break}
 }
 return (true,Array(Set(found)))
}
struct NativeRead {let row:AXUIElement;let fieldValues:[String:String];let editor:[AXUIElement];let shared:String;let sitesKnown:Bool;let sites:[String];let otpAbsent,passkeyAbsent:Bool;let shape:[String:Any]}
func targetQuery(_ t:Target)->String {
 if let url=t.urls.first,!host(url).isEmpty {return host(url)}
 if t.username.isEmpty,t.title.contains(" · 资料 ["),t.title.hasSuffix("]"),let bracket=t.title.lastIndex(of:"[") {
  let token=String(t.title[t.title.index(after:bracket)..<t.title.index(before:t.title.endIndex)])
  if token.count==12,token.allSatisfy({"0123456789abcdef".contains($0)}) {return token}
 }
 return t.title
}
func read(_ root:AXUIElement,_ t:Target,leaveOpen:Bool=false)->NativeRead? {
 var phaseStart=Date()
 let kind=t.title.contains(" · 资料 [") ? "candidate":"retainer"
 func phase(_ name:String) {
  let now=Date(),e:[String:Any]=["event":"read_phase","kind":kind,"phase":name,"seconds":now.timeIntervalSince(phaseStart)]
  phaseStart=now
  var phases=report["read_phases"] as? [[String:Any]] ?? [];phases.append(e);report["read_phases"]=phases
  if ["--delete-background","--delete-range","--delete"].contains(args.first ?? ""),let data=try? JSONSerialization.data(withJSONObject:e,options:.sortedKeys),let value=String(data:data,encoding:.utf8) {print(value);fflush(stdout)}
 }
 defer{phase("read_ended")}
 guard let (f,_)=context(root) else {report["failure_stage"]="search_context";return nil}
 phase("search_context")
 let searchQuery=""
 report["search_identity_kind"]=t.urls.isEmpty ? (searchQuery==t.title ? "exact_title":"bound_companion_title_token"):"bound_website_host"
 guard query(f,searchQuery) else{report["failure_stage"]="single_query_edit";return nil}
 // Filtering may replace the outline object. Reacquire its current model;
 // never use the pre-query AXRows reference as an identity or delete target.
 var observed:[AXUIElement]?,observedLabels:[[String]]?
 let rowLimit=3000
 if let (_,fresh)=context(root),let rows=attr(fresh,kAXRowsAttribute) as? [AXUIElement],let labels=indexedLabels,rows.count==labels.count {
  observed=rows;observedLabels=labels
 }
 phase("row_labels")
 report["last_native_result_count"]=observed?.count
 guard let rows=observed,let rowLabels=observedLabels,rows.count==rowLabels.count,rows.count<=rowLimit,front() else {report["failure_stage"]="bounded_search";return nil}
 let matches=zip(rows,rowLabels).filter{_,vs in vs.contains(t.title) && (t.username.isEmpty || vs.contains(t.username))}.map{$0.0}
 var rowShape:[String:Any]=[:]
 rowShape["exact_title_rows"]=rowLabels.filter{$0.contains(t.title)}.count
 rowShape["exact_account_rows"]=rowLabels.filter{$0.contains(t.username)}.count
 rowShape["title_separate_line_rows"]=rowLabels.filter{ls in ls.contains{v in v.components(separatedBy:CharacterSet.newlines).contains(t.title)}}.count
 rowShape["account_separate_line_rows"]=rowLabels.filter{ls in ls.contains{v in v.components(separatedBy:CharacterSet.newlines).contains(t.username)}}.count
 rowShape["title_prefix_rows"]=rowLabels.filter{ls in ls.contains{$0.hasPrefix(t.title)}}.count
 rowShape["account_contained_rows"]=rowLabels.filter{ls in ls.contains{$0.contains(t.username)}}.count
 rowShape["sample_row_roles"]=rows.prefix(8).map{text($0,kAXRoleAttribute)}
 rowShape["sample_row_identifiers_present"]=rows.prefix(8).filter{!text($0,kAXIdentifierAttribute).isEmpty}.count
 rowShape["row_is_synthetic"]=rowLabels.contains{$0.contains("apw API 测试 · 独立备注")}
 rowShape["query_exact"]=text(f,kAXValueAttribute)==searchQuery
 rowShape["sample_row_label_lengths"]=rowLabels.prefix(8).map{$0.map{$0.utf16.count}}
 report["row_identity_shape"]=rowShape
 guard matches.count==1 else{report["failure_stage"]="unique_native_row";report["last_match_count"]=matches.count;return nil}
 // AXRow's selected setter can report success without updating SwiftUI's
 // selectedRows model. Select through the current list, then observe its
 // fresh selected identity before opening any details.
 guard let (_,selectionList)=context(root),let selectionRows=attr(selectionList,kAXRowsAttribute) as? [AXUIElement] else{report["failure_stage"]="current_selection_list";return nil}
 guard let selectionLabels=indexedLabels,selectionRows.count==selectionLabels.count else{report["failure_stage"]="index_generation_changed";return nil}
 let exactIndexes=selectionLabels.indices.filter{selectionLabels[$0].contains(t.title) && (t.username.isEmpty || selectionLabels[$0].contains(t.username))}
 guard exactIndexes.count==1 else{report["failure_stage"]="unique_native_row";return nil}
 let freshMatches=exactIndexes.map{selectionRows[$0]}
 guard completeDiscovery({rowValues(freshMatches[0])})==selectionLabels[exactIndexes[0]] else{report["failure_stage"]="index_identity_changed";return nil}
 phase("fresh_identity_scan")
 guard freshMatches.count==1 else{report["failure_stage"]="current_selection_identity";return nil}
 var row=freshMatches[0];var selectionWritable=DarwinBoolean(false)
 let canSelectList=AXUIElementIsAttributeSettable(selectionList,kAXSelectedRowsAttribute as CFString,&selectionWritable) == .success && selectionWritable.boolValue
 let listSelected=canSelectList && set(selectionList,kAXSelectedRowsAttribute,[row] as CFArray)
 if !listSelected {
  guard set(row,kAXSelectedAttribute,kCFBooleanTrue) else{report["failure_stage"]="select_unique_row";report["selection_diagnostics"]=selectionDiagnostics(root);return nil}
 }
 report["selection_method"]=listSelected ? "current_list_selected_rows":"unique_current_row_then_detail_proof"
 phase("selection_action")
 let selectedUntil=Date(timeIntervalSinceNow:6);var view:[AXUIElement]=[];var edit:AXUIElement?;var selected=false
 while front(),Date()<selectedUntil {
  view=nodes(root)
  if let (_,list)=context(root),let selectedRows=attr(list,kAXSelectedRowsAttribute) as? [AXUIElement] {
   let own=selectedRows.filter{let labels=rowValues($0);return labels.contains(t.title) && (t.username.isEmpty || labels.contains(t.username))}
   if selectedRows.count==1,own.count==1 {row=own[0];selected=true}
  }
  let detailValues=values(view)
  let boundDetail=detailValues.contains(t.title) && (t.notes.isEmpty || detailValues.contains(t.notes)) && (t.username.isEmpty || detailValues.contains(t.username))
  selected=selected || boundDetail
  edit=button(view,["编辑","Edit","编辑密码","Edit Password","编辑备注","Edit Note"])
  if selected,edit != nil {break};pause(0.05)
 }
 phase("detail_binding")
 report["selection_context"]=["selected_identity_confirmed":selected,"edit_button_unique":edit != nil]
 let group=sharing(view)
 let detailSnapshot=values(view)
 let boundView=detailSnapshot.contains(t.title) && (t.notes.isEmpty || detailSnapshot.contains(t.notes)) && (t.username.isEmpty || detailSnapshot.contains(t.username))
 guard selected,let edit,press(edit) else{report["failure_stage"]="open_readonly_editor";report["selection_diagnostics"]=selectionDiagnostics(root);return nil}
 pause(0.12)
 let wantedHosts=Set(t.urls.map(host));let siteUntil=Date(timeIntervalSinceNow:1.5)
 var ns=nodes(root);var fs=fields(ns);var sites=websites(ns)
 while front(),!wantedHosts.isEmpty,!wantedHosts.isSubset(of:Set(sites.1.map(host))),Date()<siteUntil {
  pause(0.05);ns=nodes(root);fs=fields(ns);sites=websites(ns)
 }
 let form=formNodes(ns)
 let forbidden=form.filter{["AXButton","AXStaticText","AXLink"].contains(text($0,kAXRoleAttribute)) && !["NotesField","TitleField","UserNameField","PasswordField"].contains(text($0,kAXIdentifierAttribute))}.flatMap{values([$0])}.contains{ s in
  let lower=s.lowercased();return (s.contains("通行密钥") || lower.contains("passkey")) && !s.contains("添加通行密钥") && !lower.contains("add passkey") && !s.contains("进一步了解") && !lower.contains("learn more")
 }
 let setupNames=["设置密钥","Set Up Key","设置密钥…","Set Up Key…","设置密钥...","Set Up Key...","设置验证码","Set Up Verification Code","设置验证码…","Set Up Verification Code…","设置验证码...","Set Up Verification Code...","添加验证码","Add Verification Code","添加验证码…","Add Verification Code…"]
 let setupButtons=form.filter{text($0,kAXRoleAttribute)=="AXButton" && values([$0]).contains(where:{setupNames.contains($0)})}
 let codeLabels=form.filter{text($0,kAXIdentifierAttribute)=="VerificationCodeField"}
 let codeLabelKnown=codeLabels.count==1 && text(codeLabels[0],kAXRoleAttribute)=="AXStaticText"
 let noOTP = codeLabelKnown && setupButtons.count==1
 let shape:[String:Any]=["website_add_field_empty":fs["WebsiteField"]=="","verification_field_empty":fs["VerificationCodeField"]=="","form_root_found":!form.isEmpty,"verification_identifiers":Set(form.map{text($0,kAXIdentifierAttribute)}.filter{$0.lowercased().contains("verification")}).sorted(),"support_link_candidates":sites.1.filter{host($0)=="support.apple.com"}.count,"verification_label_recognized":codeLabelKnown,"setup_code_button_count":setupButtons.count]
 var detailShape=shape
 let safeSiteNodes=ns.filter{!["TitleField","NotesField","UserNameField","PasswordField"].contains(text($0,kAXIdentifierAttribute))}
 let exactSiteNodes=safeSiteNodes.filter{n in values([n]).contains{v in t.urls.contains(v) || wantedHosts.contains(v)}}
 detailShape["website_structure"]=["exact_website_nodes":exactSiteNodes.count,"exact_website_roles":exactSiteNodes.map{text($0,kAXRoleAttribute)},
  "form_contains_exact_website":form.contains{n in exactSiteNodes.contains{CFEqual(n,$0)}},
  "exact_site_section_identifier":exactSiteNodes.map{text($0,kAXIdentifierAttribute)=="WebsiteField"},
  "exact_site_under_label_parent":ns.filter{text($0,kAXIdentifierAttribute)=="WebsiteField"}.map{n->Bool in
   guard let p=attr(n,kAXParentAttribute),CFGetTypeID(p)==AXUIElementGetTypeID() else{return false}
   let pn=nodes(unsafeBitCast(p,to:AXUIElement.self));return pn.contains{child in exactSiteNodes.contains{CFEqual(child,$0)}}
  },
  "other_editable_count":safeSiteNodes.filter{additionalEditableData(text($0,kAXRoleAttribute),text($0,kAXIdentifierAttribute),text($0,kAXValueAttribute))}.count,
  "site_section_parent_roles":safeSiteNodes.filter{text($0,kAXIdentifierAttribute)=="WebsiteField"}.map{n-> [String] in
   var current=n;var roles:[String]=[]
   for _ in 0..<8 {guard let p=attr(current,kAXParentAttribute),CFGetTypeID(p)==AXUIElementGetTypeID() else{break};current=unsafeBitCast(p,to:AXUIElement.self);roles.append(text(current,kAXRoleAttribute))}
   return roles
  }]
 for id in ["WebsiteField","VerificationCodeField"] {
  if let node=ns.first(where:{text($0,kAXIdentifierAttribute)==id}) {
   let value=text(node,kAXValueAttribute),placeholder=text(node,"AXPlaceholderValue")
   detailShape[id] = ["role":text(node,kAXRoleAttribute),"value_matches_placeholder":!placeholder.isEmpty && value==placeholder,
   "known_static_label": ["网站","网址","网站地址","URL","Website","Websites","website","websites","网站 URL","网站URL","无网站","无网址","未提供","未设置","无","None","No Website","No Websites"].first{sectionLabel(value)==$0} ?? "unrecognized",
   "value_length":value.utf16.count,
   "is_add_website_hint":["添加网站","Add Website","添加网站…","Add Website…"].contains(value),
   "is_setup_code_hint":["设置密钥","Set Up Key","设置密钥…","Set Up Key…","设置验证码","Set Up Verification Code","输入密钥","Enter Key"].contains(value)]
  }
 }
 phase("editor_fields")
 let currentSharing=sharing(ns)
 let effectiveSharing=currentSharing=="unshared" ? currentSharing:(boundView ? group:"unknown")
 let n=NativeRead(row:row,fieldValues:fs,editor:ns,shared:effectiveSharing,sitesKnown:sites.0,sites:sites.1,otpAbsent:noOTP,passkeyAbsent:!form.isEmpty && sites.0 && sites.1.isEmpty && t.username.isEmpty && !forbidden,shape:detailShape)
 if !leaveOpen, !cancel(root,n) {report["failure_stage"]="cancel_readonly_editor";return nil}
 return n
}
func cancel(_ root:AXUIElement,_ n:NativeRead)->Bool {
 let ns=nodes(root)
 report["cancel_context"]=["foreground":front(),"fields_unchanged":fields(ns)==n.fieldValues,"selected_row":attr(n.row,kAXSelectedAttribute) as? Bool==true,"cancel_button_unique":button(ns,["取消","Cancel"]) != nil]
 guard front(),fields(ns)==n.fieldValues,let b=button(ns,["取消","Cancel"]),press(b) else{return false}
 pause(0.1);return context(root) != nil
}
func apple(_ pid:pid_t)->Bool {var c:SecCode?,r:SecRequirement?;guard SecCodeCopyGuestWithAttributes(nil,[kSecGuestAttributePid as String:pid] as CFDictionary,[],&c)==errSecSuccess,SecRequirementCreateWithString("identifier \"com.apple.Passwords\" and anchor apple" as CFString,[],&r)==errSecSuccess,let c,let r else{return false};return SecCodeCheckValidity(c,[],r)==errSecSuccess}
func ready()->AXUIElement? {
 guard nativeTimeoutSetup == .success else{report["status"]="native_timeout_setup_failed";return nil}
 guard AXIsProcessTrusted(),let a=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Passwords").first,apple(a.processIdentifier) else{report["status"]="native_access_unavailable";return nil}
 appPID=a.processIdentifier;guard front() else{report["status"]="passwords_foreground_required";return nil}
 let root=AXUIElementCreateApplication(appPID);AXUIElementSetMessagingTimeout(root,0.1)
 guard context(root) != nil else{report["status"]="locked_or_user_context_unavailable";return nil}
 report["apple_process_verified"]=true;return root
}
func categoryButton(_ root:AXUIElement,_ names:[String])->AXUIElement? {
 let base=nodes(root)
 let sidebar=base.filter{text($0,kAXRoleAttribute)=="AXOutline" && values([$0]).contains{["边栏","侧边栏","Sidebar"].contains($0)}}
 let sidebarRows=sidebar.flatMap{attr($0,kAXRowsAttribute) as? [AXUIElement] ?? []}
 let categoryGrid=sidebarRows.flatMap{row->[AXUIElement] in
  let ns=nodes(row,prune:false),bs=ns.filter{text($0,kAXRoleAttribute)=="AXButton"}
  guard bs.count==6,values(bs).contains(where:{$0.contains("全部") || $0.contains("All")}),values(bs).contains(where:{$0.contains("已删除") || $0.contains("Deleted")}) else{return []}
  return bs
 }
 let all=base+sidebarRows.flatMap{nodes($0,prune:false)}
 report["sidebar_graph"]=["outline_count":sidebar.count,"row_counts":sidebar.map{(attr($0,kAXRowsAttribute) as? [AXUIElement])?.count ?? -1},
  "rows":sidebar.flatMap{(attr($0,kAXRowsAttribute) as? [AXUIElement] ?? []).map{row->[String:Any] in
   let children=nodes(row,prune:false)
   return ["roles":children.map{text($0,kAXRoleAttribute)},"string_lengths":children.map{values([$0]).map{$0.utf16.count}},
    "all_label_parts":children.map{values([$0]).contains{$0.contains("全部") || $0.hasPrefix("All")}},
    "deleted_label_parts":children.map{values([$0]).contains{$0.contains("已删除") || $0.hasPrefix("Deleted")}}]
  }}]
 func known(_ n:AXUIElement)->Bool {values([n]).contains{v in
  if categoryGrid.contains(where:{CFEqual($0,n)}) {return names.contains{v.contains($0)}}
  return names.contains{v==$0 || v.hasPrefix($0+", ") || v.hasPrefix($0+"，") || v.hasPrefix($0+"\n")}
 }}
 var matches:[AXUIElement]=[]
 for n in all where known(n) {
  var current=n
  for _ in 0..<4 {
   if ["AXButton","AXRadioButton","AXRow"].contains(text(current,kAXRoleAttribute)) {
    if !matches.contains(where:{CFEqual($0,current)}) {matches.append(current)}
    break
   }
   guard let parent=attr(current,kAXParentAttribute),CFGetTypeID(parent)==AXUIElementGetTypeID() else{break}
   current=unsafeBitCast(parent,to:AXUIElement.self)
   if ["AXWindow","AXApplication","AXToolbar","AXOutline","AXTable"].contains(text(current,kAXRoleAttribute)) {break}
  }
 }
 return matches.count==1 ? matches[0]:nil
}
func sidebarAddress(_ root:AXUIElement)->(String,String)? {
 let ns=nodes(root),windows=ns.filter{text($0,kAXSubroleAttribute)=="AXStandardWindow"}
 let sidebars=ns.filter{text($0,kAXRoleAttribute)=="AXOutline" && ["边栏","侧边栏","Sidebar"].contains(text($0,kAXDescriptionAttribute))}
 guard front(),windows.count==1,sidebars.count==1 else{return nil}
 let window=windows[0],description=text(sidebars[0],kAXDescriptionAttribute)
 var current=sidebars[0],indexes:[Int]=[]
 for _ in 0..<16 {
  if CFEqual(current,window) {
   var address="apwWindow"
   for index in indexes {address="UI element \(index) of (\(address))"}
   report["all_list_sidebar_path_depth"]=indexes.count
   report["all_list_account_outline_enumerated"]=false
   return (address,description)
  }
  guard let parent=attr(current,kAXParentAttribute),CFGetTypeID(parent)==AXUIElementGetTypeID() else{return nil}
  let p=unsafeBitCast(parent,to:AXUIElement.self)
  guard !["AXOutline","AXTable","AXSheet"].contains(text(p,kAXRoleAttribute)),let children=attr(p,kAXChildrenAttribute) as? [AXUIElement] else{return nil}
  let matches=children.indices.filter{CFEqual(children[$0],current)}
  guard matches.count==1 else{return nil}
  indexes.insert(matches[0]+1,at:0);current=p
 }
 return nil
}
func clearAllListBridge(_ root:AXUIElement)->Bool {
 guard front(),let(sf,_)=context(root),let all=categoryButton(root,["全部","All"]),let deleted=categoryButton(root,["已删除","Deleted","Recently Deleted","最近删除"]) else{return false}
 // These tile captions are AXAttributedDescription, which System Events cannot
 // coerce to text. Bind their current unique AXIdentifier instead.
 let allLabel=text(all,kAXIdentifierAttribute),deletedLabel=text(deleted,kAXIdentifierAttribute),old=text(sf,kAXValueAttribute)
 guard !allLabel.isEmpty,!deletedLabel.isEmpty,let (sidebarPath,sidebarDescription)=sidebarAddress(root),!nativeObservationIncomplete else{return false}
 func encoded(_ text:String)->String {Data(text.utf8).base64EncodedString()}
 let source="""
 use framework "Foundation"
 use scripting additions
 on decode64(encoded)
  set apwBytes to current application's NSData's alloc()'s initWithBase64EncodedString:encoded options:0
  return (current application's NSString's alloc()'s initWithData:apwBytes encoding:4) as text
 end decode64
 set apwAllLabel to my decode64("\(encoded(allLabel))")
 set apwDeletedLabel to my decode64("\(encoded(deletedLabel))")
 set apwOldQuery to my decode64("\(encoded(old))")
 set apwSidebarDescription to my decode64("\(encoded(sidebarDescription))")
 set apwBridgeStage to 10
 try
 tell application "System Events"
  \(scriptOwnerGuard("unix id of first application process whose frontmost is true"))
  tell process "Passwords"
   if unix id is not \(appPID) then error "process_changed"
   set apwWindows to windows whose subrole is "AXStandardWindow"
   if (count apwWindows) is not 1 then error "window_changed"
   set apwWindow to item 1 of apwWindows
   if (count sheets of apwWindow) is not 0 then error "sheet_changed"
   set apwCategoryStep to 0
   repeat with apwCaption in {apwDeletedLabel, apwAllLabel}
    set apwCategoryStep to apwCategoryStep + 1
    set apwBridgeStage to 20 + apwCategoryStep
    set apwWindows to windows whose subrole is "AXStandardWindow"
    if (count apwWindows) is not 1 then error "window_changed"
    set apwWindow to item 1 of apwWindows
    if (count sheets of apwWindow) is not 0 then error "sheet_changed"
    set apwButtons to {}
    set apwSidebar to \(sidebarPath)
    if (value of attribute "AXRole" of apwSidebar) is not "AXOutline" then error "sidebar_changed"
    if (value of attribute "AXDescription" of apwSidebar as text) is not apwSidebarDescription then error "sidebar_changed"
    set apwBridgeStage to 30 + apwCategoryStep
    -- Enumerate only sidebar rows: the full window can contain the same tiles.
    set apwElements to {}
    set apwSidebarRows to rows of apwSidebar
    repeat with apwSidebarRow in apwSidebarRows
     set apwElements to apwElements & (entire contents of apwSidebarRow)
    end repeat
    repeat with apwElement in apwElements
     try
      if (value of attribute "AXRole" of apwElement) is "AXButton" and (value of attribute "AXIdentifier" of apwElement as text) is (apwCaption as text) then set end of apwButtons to contents of apwElement
     end try
    end repeat
    if (count apwButtons) is not 1 then error ("category_changed_" & apwCategoryStep & "_" & (count apwButtons))
    set apwBridgeStage to 40 + apwCategoryStep
    tell application "System Events" to set apwCurrentOwner to unix id of first application process whose frontmost is true
    \(scriptOwnerGuard("apwCurrentOwner"))
    set apwBridgeStage to 50 + apwCategoryStep
    click item 1 of apwButtons
    delay 0.15
   end repeat
   set apwBridgeStage to 60
   set apwWindows to windows whose subrole is "AXStandardWindow"
   if (count apwWindows) is not 1 then error "window_changed"
   set apwWindow to item 1 of apwWindows
   if (count sheets of apwWindow) is not 0 then error "sheet_changed"
   set apwSearches to {}
   set apwElements to entire contents of toolbar 1 of apwWindow
   repeat with apwElement in apwElements
    try
     if (value of attribute "AXRole" of apwElement) is "AXTextField" and (value of attribute "AXSubrole" of apwElement) is "AXSearchField" then set end of apwSearches to contents of apwElement
    end try
   end repeat
   if (count apwSearches) is not 1 then error "search_changed"
   set apwSearch to item 1 of apwSearches
   if (value of apwSearch as text) is not apwOldQuery then error "query_changed"
   if apwOldQuery is not "" then
    set apwClear to buttons of apwSearch whose description is "取消"
    if (count apwClear) is not 1 then set apwClear to buttons of apwSearch whose description is "Cancel"
    if (count apwClear) is not 1 then error "clear_changed"
    set apwBridgeStage to 70
    click item 1 of apwClear
   end if
  end tell
 end tell
 on error number apwBridgeError
  error ("all_list_stage_" & apwBridgeStage & "_code_" & apwBridgeError)
 end try
 return "all_cleared"
 """
 let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/osascript");process.arguments=["-"]
 let input=Pipe(),output=Pipe(),error=Pipe();process.standardInput=input;process.standardOutput=output;process.standardError=error
 do{try process.run();input.fileHandleForWriting.write(Data(source.utf8));try input.fileHandleForWriting.close()}catch{return false}
 let until=Date(timeIntervalSinceNow:12)
 while process.isRunning,Date()<until{pause(0.02)}
 if process.isRunning{process.terminate();report["all_list_bridge_timed_out"]=true;return false}
 report["all_list_bridge_exit_code"]=process.terminationStatus
 let response=String(data:output.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines)
 let diagnostic=String(data:error.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8) ?? ""
 report["all_list_bridge_failure"]=["owner_changed","process_changed","window_changed","sheet_changed","sidebar_changed","category_changed","search_changed","query_changed","clear_changed"].first{diagnostic.contains($0)} ?? (process.terminationStatus==0 ? "none":"unclassified_system_events_error")
 if let pattern=try? NSRegularExpression(pattern:"category_changed_([0-9]+)_([0-9]+)"),let match=pattern.firstMatch(in:diagnostic,range:NSRange(diagnostic.startIndex...,in:diagnostic)),let step=Range(match.range(at:1),in:diagnostic),let count=Range(match.range(at:2),in:diagnostic) {
  report["all_list_bridge_category_step"]=Int(diagnostic[step]);report["all_list_bridge_category_match_count"]=Int(diagnostic[count])
 }
 if let pattern=try? NSRegularExpression(pattern:"all_list_stage_([0-9]+)_code_(-?[0-9]+)"),let match=pattern.firstMatch(in:diagnostic,range:NSRange(diagnostic.startIndex...,in:diagnostic)),let step=Range(match.range(at:1),in:diagnostic),let code=Range(match.range(at:2),in:diagnostic) {
  report["all_list_bridge_stage"]=Int(diagnostic[step]);report["all_list_bridge_error_code"]=Int(diagnostic[code])
 }
 return process.terminationStatus==0 && response=="all_cleared" && front()
}

// The list is indexed once per category/generation, not twice per record.
// A fresh row at that index must still have the exact complete cached labels.
// ponytail: sorted-list index, not a permanent record ID; any mismatch stops.
var activeLabels:[[String]]?
var deletedLabels:[[String]]?
var currentCategory=""
var ownEditor:(AXUIElement,NativeRead)?
var ownEditorFields:[String:String]?
func closeOwnEditor() {
 guard let (root,n)=ownEditor,let expected=ownEditorFields,front() else{return}
 var current=nodes(root)
 guard fields(current)==expected else{return}
 let sheets=current.filter{text($0,kAXRoleAttribute)=="AXSheet"}
 if sheets.count==1,let back=button(nodes(sheets[0]),["取消","Cancel"]),press(back) {pause(0.1);current=nodes(root)}
 guard !current.contains(where:{text($0,kAXRoleAttribute)=="AXSheet"}),fields(current)==expected else{return}
 let observed=NativeRead(row:n.row,fieldValues:expected,editor:current,shared:n.shared,sitesKnown:n.sitesKnown,sites:n.sites,otpAbsent:n.otpAbsent,passkeyAbsent:n.passkeyAbsent,shape:n.shape)
 if cancel(root,observed) {ownEditor=nil;ownEditorFields=nil}
}
func nativeFailure(_ name:String)->NSError {NSError(domain:"APWMaintenance",code:1,userInfo:[NSLocalizedDescriptionKey:"maintenance_"+name])}
func require(_ ok:Bool,_ name:String)throws {if !ok {throw nativeFailure(name)}}
func freshRoot()throws->AXUIElement {
 guard let r=ready() else{throw nativeFailure("locked_or_access_unavailable")}
 return r
}
func boundedClick(_ node:AXUIElement,_ root:AXUIElement)->Bool {
 guard owned(node) else{return false}
 if press(node) {return true}
 // System Events sometimes exposes AXPress when the native AX client does not.
 // Resolve only this element's address; never enumerate the account outline.
 let ws=nodes(root).filter{text($0,kAXSubroleAttribute)=="AXStandardWindow"}
 guard ws.count==1 else{return false}
 let w=ws[0],id=text(node,kAXIdentifierAttribute),role=text(node,kAXRoleAttribute)
 let captionAttribute=text(node,kAXTitleAttribute).isEmpty ? kAXDescriptionAttribute:kAXTitleAttribute
 let caption=text(node,captionAttribute)
 guard !id.isEmpty || !caption.isEmpty else{return false}
 var current=node,indexes:[Int]=[]
 for _ in 0..<24 {
  if CFEqual(current,w) {break}
  guard let parent=attr(current,kAXParentAttribute),CFGetTypeID(parent)==AXUIElementGetTypeID() else{return false}
  let p=unsafeBitCast(parent,to:AXUIElement.self)
  // Never generate an address through the full account table.
  guard text(p,kAXIdentifierAttribute) != "AccountListView",let cs=attr(p,kAXChildrenAttribute) as? [AXUIElement],cs.count<100 else{return false}
  let found=cs.indices.filter{CFEqual(cs[$0],current)};guard found.count==1 else{return false}
  indexes.insert(found[0]+1,at:0);current=p
 }
 guard CFEqual(current,w) else{return false}
 var address="apwWindow";for i in indexes {address="UI element \(i) of (\(address))"}
 let encoded=Data(id.utf8).base64EncodedString()
 let captionEncoded=Data(caption.utf8).base64EncodedString()
 let source="""
 use framework "Foundation"
 use scripting additions
 set bytes to current application's NSData's alloc()'s initWithBase64EncodedString:"\(encoded)" options:0
 set expectedID to (current application's NSString's alloc()'s initWithData:bytes encoding:4) as text
 set captionBytes to current application's NSData's alloc()'s initWithBase64EncodedString:"\(captionEncoded)" options:0
 set expectedCaption to (current application's NSString's alloc()'s initWithData:captionBytes encoding:4) as text
 tell application "System Events"
  \(scriptOwnerGuard("unix id of first application process whose frontmost is true"))
  tell process "Passwords"
   if unix id is not \(appPID) then error "process_changed"
   set ws to windows whose subrole is "AXStandardWindow"
   if (count ws) is not 1 then error "window_changed"
   set apwWindow to item 1 of ws
   if (count sheets of apwWindow) is not 0 then error "sheet_changed"
   set apwElement to \(address)
   if (value of attribute "AXRole" of apwElement as text) is not "\(role)" then error "role_changed"
   if (value of attribute "AXIdentifier" of apwElement as text) is not expectedID then error "identity_changed"
   if expectedID is "" and (value of attribute "\(captionAttribute)" of apwElement as text) is not expectedCaption then error "caption_changed"
   tell application "System Events" to set apwOwner to unix id of first application process whose frontmost is true
   \(scriptOwnerGuard("apwOwner"))
   click apwElement
  end tell
 end tell
 return "clicked"
 """
 let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/osascript");p.arguments=["-"]
 let input=Pipe(),output=Pipe();p.standardInput=input;p.standardOutput=output;p.standardError=FileHandle.nullDevice
 do {try p.run();input.fileHandleForWriting.write(Data(source.utf8));try input.fileHandleForWriting.close()}catch{return false}
 let until=Date(timeIntervalSinceNow:8);while p.isRunning,Date()<until {pause(0.02)}
 if p.isRunning {p.terminate();return false}
 return p.terminationStatus==0 && front() && String(data:output.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines)=="clicked"
}
func selectCategory(_ root:AXUIElement,_ category:String)throws {
 guard let (f,_)=context(root) else{throw nativeFailure("locked_or_user_editor")}
 if currentCategory.isEmpty,!text(f,kAXValueAttribute).isEmpty {
  // Clear with the actual search cancel action, not an AXValue write that
  // SwiftUI might accept without updating its model. Owner guards still apply.
  try require(clearAllListBridge(root),"initial_list_preparation_failed")
  currentCategory="active"
 }
 guard let (currentSearch,_)=context(root) else{throw nativeFailure("locked_or_user_editor")}
 try require(text(currentSearch,kAXValueAttribute).isEmpty,"filtered_list_refused")
 if currentCategory != category {
  let names=category=="active" ? ["全部","All"]:["已删除","Deleted","Recently Deleted","最近删除"]
  guard let b=categoryButton(root,names) else{throw nativeFailure("category_ambiguous")}
  try require(boundedClick(b,root),"category_selection_failed")
  pause(0.15);currentCategory=category
 }
 guard let (_,list)=context(root),let rows=attr(list,kAXRowsAttribute) as? [AXUIElement],rows.count<=3000 else{throw nativeFailure("list_unavailable")}
 let cached=category=="active" ? activeLabels:deletedLabels
 if let cached {
  try require(cached.count==rows.count,"index_generation_changed");indexedLabels=cached
 } else {
  guard let labels=completeDiscovery({rows.map{rowValues($0)}}) else{throw nativeFailure("incomplete_discovery_snapshot")}
  if category=="active" {activeLabels=labels}else{deletedLabels=labels};indexedLabels=labels
 }
}
func snapshot(_ key:[String:String],_ n:NativeRead)throws->[String:Any] {
 let fs=n.fieldValues
 guard let title=fs["TitleField"],let user=fs["UserNameField"],let password=fs["PasswordField"],let notes=fs["NotesField"] else{throw nativeFailure("snapshot_incomplete")}
 try require(user==key["username"] && n.sitesKnown && !nativeObservationIncomplete,"snapshot_incomplete")
 let form=formNodes(n.editor)
 let extra=form.filter{additionalEditableData(text($0,kAXRoleAttribute),text($0,kAXIdentifierAttribute),text($0,kAXValueAttribute))}.map{n in
  ["role":text(n,kAXRoleAttribute),"id":text(n,kAXIdentifierAttribute),"value":text(n,kAXValueAttribute)]
 }.sorted{($0["id"] ?? "")<($1["id"] ?? "")}
 return ["key":key,"native_title":title,"notes":notes,"password":password,"sites":n.sites.sorted(),"sharing":n.shared,
  "otp":n.otpAbsent ? "absent":"unknown","passkey":n.passkeyAbsent ? "absent":"unknown","extra_fields":extra]
}
func readKey(_ key:[String:String],_ category:String="active",leaveOpen:Bool=false)throws->(AXUIElement,NativeRead,[String:Any]) {
 let root=try freshRoot();try selectCategory(root,category)
 guard let title=key["title"],!title.isEmpty,let user=key["username"],let labels=indexedLabels else{throw nativeFailure("identity_invalid")}
 let matches=labels.filter{$0.contains(title) && (user.isEmpty || $0.contains(user))}
 try require(matches.count>0,"item_not_found");try require(matches.count==1,"item_ambiguous")
 let target=Target(title:title,native_title:title,username:user,notes:"",urls:[])
 guard let n=read(root,target,leaveOpen:true) else {
  let stage=report["failure_stage"] as? String ?? "unknown"
  throw nativeFailure("native_read_"+(stage.allSatisfy({$0.isLowercase || $0=="_"}) ? stage:"unknown"))
 }
 ownEditor=(root,n);ownEditorFields=n.fieldValues
 let value:[String:Any]
 do {value=try snapshot(key,n)} catch { _=cancel(root,n);throw error }
 if !leaveOpen {try require(cancel(root,n),"editor_cancel_unverified");ownEditor=nil;ownEditorFields=nil}
 return (root,n,value)
}
func equalState(_ a:[String:Any],_ b:[String:Any])->Bool {NSDictionary(dictionary:a).isEqual(to:b)}
func deletedNote(_ key:[String:String],_ expected:[String:Any])throws->[String:Any] {
 // Recently Deleted is immutable until recovery. Verify the complete note in
 // its detail view, rather than trying to open a nonexistent edit form.
 try require((expected["key"] as? [String:String])==key && key["username"]=="" &&
  expected["password"] as? String=="" && (expected["sites"] as? [String])?.isEmpty==true &&
  expected["otp"] as? String=="absent" && expected["passkey"] as? String=="absent" &&
  expected["sharing"] as? String=="unshared" && (expected["extra_fields"] as? [[String:String]])?.isEmpty==true,"deleted_proof_invalid")
 guard let expectedNote=expected["notes"] as? String,!expectedNote.isEmpty else{throw nativeFailure("deleted_proof_invalid")}
 let root=try freshRoot();try selectCategory(root,"deleted")
 guard let (_,list)=context(root),let rows=attr(list,kAXRowsAttribute) as? [AXUIElement],let labels=indexedLabels,rows.count==labels.count else{throw nativeFailure("index_generation_changed")}
 let indexes=labels.indices.filter{labels[$0].contains(key["title"]!)}
 try require(indexes.count>0,"item_not_found");try require(indexes.count==1,"item_ambiguous")
 let row=rows[indexes[0]]
 try require(completeDiscovery({rowValues(row)})==labels[indexes[0]],"index_identity_changed")
 var writable=DarwinBoolean(false)
 let selected=AXUIElementIsAttributeSettable(list,kAXSelectedRowsAttribute as CFString,&writable) == .success && writable.boolValue && set(list,kAXSelectedRowsAttribute,[row] as CFArray)
 try require(selected || set(row,kAXSelectedAttribute,kCFBooleanTrue),"select_unique_row_failed")
 let until=Date(timeIntervalSinceNow:5)
 while front(),Date()<until {
  let view=nodes(root),vs=values(view)
  let recovery=button(view,["恢复密码","Recover Password","恢复","Recover","恢复备注","Recover Note","恢复密码…","Recover Password…"])
  if vs.contains(key["title"]!),vs.contains(expectedNote),recovery != nil,!nativeObservationIncomplete {
   return ["ok":true,"state":expected,"verification":"deleted_note_identity_and_full_body"]
  }
  pause(0.05)
 }
 throw nativeFailure("deleted_body_unverified")
}
func execute(_ q:[String:Any])throws->[String:Any] {
 let op=q["op"] as? String ?? ""
 if op=="doctor" {
  let running=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Passwords")
  var windowState="unknown"
  if AXIsProcessTrusted(),running.count==1,apple(running[0].processIdentifier) {
   let ns=nodes(AXUIElementCreateApplication(running[0].processIdentifier))
   if ns.contains(where:{text($0,kAXIdentifierAttribute)=="AccountListView"}) {windowState="unlocked_list_available"}
   else if ns.filter({text($0,kAXRoleAttribute)=="AXButton"}).contains(where:{n in values([n]).contains{v in v.contains("解锁") || v.lowercased().contains("unlock")}}) {windowState="locked"}
  }
  return ["ok":true,"backend":"apple-passwords-accessibility","capabilities":["read","notes-set","delete-redundant-note"],
   "apple_live_verified":false,"accessibility_trusted":AXIsProcessTrusted(),"apple_running":running.count==1,"window_state":windowState,
   "passwords_frontmost":running.count==1 && NSWorkspace.shared.frontmostApplication?.processIdentifier==running[0].processIdentifier,
   "whole_vault_public_api":false,"native_protocol_delete_assumed":false]
 }
 try require(["read","deleted-read","notes-set","delete-redundant-note"].contains(op),"operation_unsupported")
 guard let key=q["key"] as? [String:String],Set(key.keys)==Set(["title","username"]),!(key["title"] ?? "").isEmpty else{throw nativeFailure("identity_invalid")}
 if appPID==0 {
  guard let a=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Passwords").first,apple(a.processIdentifier),let original=NSWorkspace.shared.frontmostApplication?.processIdentifier else{throw nativeFailure("locked_or_access_unavailable")}
  appPID=a.processIdentifier
  if original != appPID {backgroundOwnerPID=original}
 }
 if op=="read" {return ["ok":true,"state":try readKey(key).2]}
 if op=="deleted-read" {
  guard let expected=q["expected"] as? [String:Any] else{throw nativeFailure("deleted_proof_required")}
  return try deletedNote(key,expected)
 }
 guard let expected=q["expected"] as? [String:Any] else{throw nativeFailure("preimage_required")}
 let (root,n,before)=try readKey(key,leaveOpen:true)
 guard equalState(before,expected) else{_=cancel(root,n);throw nativeFailure("preimage_changed")}
 if op=="notes-set" {
  guard let after=q["notes"] as? String,!after.isEmpty,after.utf16.count<=65536,!after.contains("\0"),after.contains(before["notes"] as? String ?? ""),n.shared=="unshared" else{_=cancel(root,n);throw nativeFailure("note_preservation_refused")}
  let fieldsNow=nodes(root).filter{text($0,kAXIdentifierAttribute)=="NotesField"}
  guard fieldsNow.count==1,fields(nodes(root))==n.fieldValues,front() else{_=cancel(root,n);throw nativeFailure("note_write_refused")}
  let note=fieldsNow[0],old=before["notes"] as? String ?? "",ownerBefore=NSWorkspace.shared.frontmostApplication?.processIdentifier,keyboardBefore=focusPID()
  var rangeWritable=DarwinBoolean(false),textWritable=DarwinBoolean(false)
  // AXValue changed the visible editor without changing SwiftUI's saved model
  // in the live synthetic test. Complete SelectedText replacement is the only
  // supported write path; no field focus or injected input is used.
  guard AXUIElementIsAttributeSettable(note,kAXSelectedTextRangeAttribute as CFString,&rangeWritable) == .success,rangeWritable.boolValue,
   AXUIElementIsAttributeSettable(note,kAXSelectedTextAttribute as CFString,&textWritable) == .success,textWritable.boolValue else{_=cancel(root,n);throw nativeFailure("note_text_replacement_unsupported")}
  var full=CFRange(location:0,length:old.utf16.count)
  guard let selection=AXValueCreate(.cfRange,&full),set(note,kAXSelectedTextRangeAttribute,selection),let seen=attr(note,kAXSelectedTextRangeAttribute),CFGetTypeID(seen)==AXValueGetTypeID() else{throw nativeFailure("note_selection_unverified")}
  var actual=CFRange();try require(AXValueGetValue(unsafeBitCast(seen,to:AXValue.self),.cfRange,&actual) && actual.location==0 && actual.length==full.length,"note_selection_unverified")
  try require(set(note,kAXSelectedTextAttribute,after as CFString),"note_text_replacement_refused")
  try require(NSWorkspace.shared.frontmostApplication?.processIdentifier==ownerBefore && focusPID()==keyboardBefore && front(),"note_owner_changed")
  let current=fields(nodes(root));var wanted=n.fieldValues;wanted["NotesField"]=after
  if current.filter({$0.key != "NotesField"})==n.fieldValues.filter({$0.key != "NotesField"}),current["NotesField"] != nil {ownEditorFields=current}
  guard current==wanted,!nativeObservationIncomplete,let save=button(nodes(root),["保存","Save","完成","Done"]),boundedClick(save,root) else{throw nativeFailure("note_save_unverified")}
  pause(0.15);try require(context(root) != nil,"note_save_unverified")
  ownEditor=nil;ownEditorFields=nil
  // Readback is performed independently by the CLI before it journals done.
  return ["ok":true]
 }
 let candidateOnly=(before["password"] as? String)=="" && key["username"]=="" && n.sites.isEmpty && n.sitesKnown &&
  n.otpAbsent && n.passkeyAbsent && n.shared=="unshared" && (before["extra_fields"] as? [[String:String]])?.isEmpty==true
 guard candidateOnly,fields(nodes(root))==n.fieldValues else{_=cancel(root,n);throw nativeFailure("redundant_note_proof_refused")}
 let bs=nodes(root).filter{text($0,kAXRoleAttribute)=="AXButton" && text($0,kAXIdentifierAttribute)=="DeleteButton"}
 guard bs.count==1,boundedClick(bs[0],root) else{_=cancel(root,n);throw nativeFailure("delete_entry_refused")}
 pause(0.1)
 let sheets=nodes(root).filter{text($0,kAXRoleAttribute)=="AXSheet"}
 try require(sheets.count==1,"delete_confirmation_unverified")
 let ns=nodes(sheets[0]),words=values(ns)
 let recover=words.contains{$0.contains("已删除") || $0.contains("30") || $0.contains("恢复") || $0.lowercased().contains("recently deleted") || $0.lowercased().contains("recover")}
 let permanent=button(ns,["永久删除","立即永久删除","Delete Permanently","Permanently Delete"]) != nil
 let confirm=button(ns,["删除密码","删除备注","删除此密码","删除","Delete Password","Delete Note","Delete"])
 try require(recover && !permanent && confirm != nil && fields(nodes(root))==n.fieldValues && !nativeObservationIncomplete,"recoverable_confirmation_refused")
 let note=before["notes"] as? String ?? ""
 let syntheticItem=Item(id:"native-maintenance",title:key["title"]!,expected_note:note,source_ids:[],retained:Target(title:"",native_title:"",username:"",notes:"",urls:[]))
 try require(confirmRecoverable(syntheticItem),"delete_outcome_requires_review")
 ownEditor=nil;ownEditorFields=nil
 pause(0.15)
 guard let (_,list)=context(root),let rows=attr(list,kAXRowsAttribute) as? [AXUIElement],var labels=activeLabels,
  let index=labels.firstIndex(where:{$0.contains(key["title"]!)}),rows.count==labels.count-1 else{throw nativeFailure("delete_outcome_requires_review")}
 labels.remove(at:index);activeLabels=labels;indexedLabels=labels;deletedLabels=nil
 return ["ok":true,"recoverable":true]
}

// A single process owns one list index for the complete bounded CLI batch.
guard args==["--serve"] else {fputs("maintenance_invalid_entry_point\n",stderr);exit(2)}
while let line=readLine(strippingNewline:true) {
 deadline=Date(timeIntervalSinceNow:90);nativeObservationIncomplete=false
 report["failure_stage"]=nil
 var response:[String:Any]=["ok":false,"app_activated":false,"backend":"apple-passwords-accessibility"]
 do {
  guard line.utf8.count<=4*1024*1024,let bytes=line.data(using:.utf8),let q=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],let id=q["id"] as? Int else{throw nativeFailure("request_invalid")}
  response["id"]=id
  response.merge(try execute(q)){_,new in new}
 } catch {
  closeOwnEditor()
  let message=(error as NSError).localizedDescription
  response["error"]=message.hasPrefix("maintenance_") && message.dropFirst(12).allSatisfy({$0.isLowercase || $0=="_"}) ? message:"maintenance_native_operation_failed"
 }
 if let bytes=try? JSONSerialization.data(withJSONObject:response,options:[.sortedKeys]),let text=String(data:bytes,encoding:.utf8) {print(text);fflush(stdout)}
}
closeOwnEditor()
