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
// A lease belongs to a request, not to the lifetime of the helper process.
// It cannot be rebound while an owned editor is open.
func requestLeaseMode(foreground:pid_t,passwords:pid_t,keyboard:pid_t?,ownedEditor:Bool)->String {
 if ownedEditor {return "preserve"}
 guard foreground>0,passwords>0 else{return "refuse"}
 if foreground==passwords {return keyboard==passwords ? "foreground":"refuse"}
 return keyboard==passwords ? "refuse":"background"
}
func unavailableContextStatus(editor:Bool,incomplete:Bool)->String {
 // Text in a row or note (including "unlocked") cannot establish a lock
 // screen. No authenticated-access permission follows from this status.
 incomplete ? "incomplete_window_observation":(editor ? "user_editor_open":"unavailable")
}
func queryStrategy(rangeSettable:Bool,textSettable:Bool,valueSettable:Bool=false)->String {
 rangeSettable && textSettable ? "selected-text":(valueSettable ? "witnessed-value":"unfiltered-index")
}
func acceptsSearchWitness(emptySeen:Bool,stableComplete:Bool,ownerUnchanged:Bool,count:Int)->Bool {
 emptySeen && stableComplete && ownerUnchanged && count>0 && count<=100
}
func recoverableDialog(words:[String],ordinaryButton:Bool,permanentButton:Bool)->Bool {
 ordinaryButton && !permanentButton && words.contains { value in
  let s=value.lowercased()
  return value.contains("已删除") || value.contains("最近删除") || value.contains("恢复") || s.contains("recently deleted") || s.contains("recover")
 }
}
func addressedSelectionScope(role:String,identifier:String,subrole:String)->Bool {
 (identifier=="NotesField" && ["AXTextArea","AXTextField"].contains(role)) || (subrole=="AXSearchField" && role=="AXTextField")
}
func requiresQueryClear(fullIndex:Bool,queryEmpty:Bool)->Bool {fullIndex && !queryEmpty}
func recoveryVerificationFieldsSafe(_ roles:[String])->Bool {
 !roles.contains{["AXTextField","AXTextArea","AXComboBox"].contains($0)}
}
func notesWritePermits(role:String,rangeCode:Int,textCode:Int,valueCode:Int,rangeSettable:Bool,textSettable:Bool,twoFrames:Bool,fieldsEqual:Bool)->Bool {
 ["AXTextField","AXTextArea"].contains(role) && twoFrames && fieldsEqual &&
 rangeCode==0 && textCode==0 && rangeSettable && textSettable &&
 [0,Int(AXError.attributeUnsupported.rawValue)].contains(valueCode)
}
func categoryCaptionMatches(_ value:String,_ category:String)->Bool {
 let names=category=="active" ? ["全部","All"]:["已删除","Deleted","Recently Deleted","最近删除"]
 let value=value.trimmingCharacters(in:CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn:"\u{200e}\u{200f}")))
 return names.contains { name in
  value==name || value.hasPrefix(name+", ") || value.hasPrefix(name+"，") || value.hasPrefix(name+"\n") ||
  ["正在搜索“\(name)”","正在搜索「\(name)」","Searching “\(name)”","Searching \"\(name)\""].contains(value)
 }
}
func editorRecoveryPermits(expected:[String:Any],observed:[String:Any],complete:Bool,unique:Bool)->Bool {
 guard complete,unique,let key=expected["key"] as? [String:String],Set(key.keys)==Set(["title","username"]),!(key["title"] ?? "").isEmpty,
  ["native_title","notes","password","sharing","otp","passkey"].allSatisfy({expected[$0] is String}),
  expected["sites"] is [String],expected["extra_fields"] is [[String:String]],
  Set(expected.keys)==Set(["key","native_title","notes","password","sites","sharing","otp","passkey","extra_fields"]) else{return false}
 return NSDictionary(dictionary:expected).isEqual(to:observed)
}
func notesProbeFixtureValid(_ expected:[String:Any])->Bool {
 guard editorRecoveryPermits(expected:expected,observed:expected,complete:true,unique:true),
  let key=expected["key"] as? [String:String],let title=key["title"],title.hasPrefix("apw API 测试"),
  (expected["native_title"] as? String)?.hasPrefix("apw API 测试")==true,
  let username=key["username"],username.isEmpty || username.lowercased().hasSuffix(".invalid"),
  (expected["notes"] as? String)?.contains("APW_EXCHANGE_SYNTHETIC_V1")==true,
  expected["password"] as? String=="",expected["sharing"] as? String=="unshared",
  let extra=expected["extra_fields"] as? [[String:String]],extra.isEmpty,
  let sites=expected["sites"] as? [String] else{return false}
 return sites.allSatisfy{host($0).hasSuffix(".invalid")}
}
func notesProbeBoundaryPermits(expected:[String:Any],syntheticOnly:Bool,count:Int,complete:Bool,stable:Bool,unique:Bool,noEditor:Bool,ownerBound:Bool)->Bool {
 syntheticOnly && notesProbeFixtureValid(expected) && count>0 && count<=100 && complete && stable && unique && noEditor && ownerBound
}
func notesProbeOutcomePermits(preimageExact:Bool,diagnosticsComplete:Bool,cancelVerified:Bool,rereadExact:Bool,finalCancelVerified:Bool)->Bool {
 preimageExact && diagnosticsComplete && cancelVerified && rereadExact && finalCancelVerified
}
func notesProbeFocusMatches(copyCode:Int,pidCode:Int,roleCode:Int,samePID:Bool,ancestorBound:Bool,role:String)->Bool {
 copyCode==0 && pidCode==0 && roleCode==0 && samePID && ancestorBound && ["AXTextField","AXTextArea","AXComboBox"].contains(role)
}
// These permissions apply only to explicit foreground synthetic operations.
// Ordinary foreground/background leases remain unchanged.
func notesProbeForegroundOwnerPermits(original:pid_t,foreground:pid_t,passwords:pid_t,keyboard:pid_t?,deadlineValid:Bool,internalComplete:Bool,internalBound:Bool)->Bool {
 passwords>0 && original==passwords && foreground==original &&
 (keyboard==nil || keyboard==passwords) && deadlineValid && internalComplete && internalBound
}
func notesProbeFocusSetterPermits(requested:Bool,expected:[String:Any],ownedEditor:Bool,twoFrames:Bool,stateExact:Bool,uniqueNote:Bool,samePID:Bool,completeScope:Bool,identifier:String,role:String,ownerValid:Bool,settableCode:Int,settable:Bool)->Bool {
 requested && notesProbeFixtureValid(expected) && ownedEditor && twoFrames && stateExact && uniqueNote && samePID && completeScope &&
 identifier=="NotesField" && ["AXTextField","AXTextArea"].contains(role) && ownerValid && settableCode==0 && settable
}
func notesProbeErrorCleanupPermits(expected:[String:Any],first:[String:Any],second:[String:Any],complete:Bool,ownedEditor:Bool,ownerValid:Bool,rawEqual:Bool)->Bool {
 notesProbeFixtureValid(expected) && complete && ownedEditor && ownerValid && rawEqual &&
 editorRecoveryPermits(expected:expected,observed:first,complete:complete,unique:true) &&
 editorRecoveryPermits(expected:expected,observed:second,complete:complete,unique:true)
}
func notesProbeForegroundFocusOption(_ value:Any?)->Bool? {
 guard let value else{return false}
 guard CFGetTypeID(value as CFTypeRef)==CFBooleanGetTypeID() else{return nil}
 return value as? Bool
}
func notesProbeReadCleanupPolicy(returnedComplete:Bool,openedByRead:Bool,ownerUnchanged:Bool,expectedComplete:Bool,listAvailable:Bool,inputAttempted:Bool=false)->String {
 if returnedComplete,openedByRead {return "register_before_snapshot"}
 if inputAttempted {return "requires_review"}
 if openedByRead,ownerUnchanged,expectedComplete {return "recover_expected_once"}
 return listAvailable ? "no_owned_editor":"requires_review"
}
// This separate synthetic mutation policy is never used by notes-set. A
// filtered diagnostic cohort is not an identity authorization for input.
func syntheticNotesAppendPermits(_ expected:[String:Any],_ after:String)->Bool {
 guard notesProbeFixtureValid(expected),let key=expected["key"] as? [String:String],
  let title=key["title"],["apw API 测试 · SSO 与备注","apw API 测试 · 独立备注"].contains(title),
  expected["native_title"] as? String==title,let old=expected["notes"] as? String,
  !after.contains("\0") else{return false}
 let original=Array(old.utf16),replacement=Array(after.utf16)
 guard replacement.count>original.count,replacement.count<=4096,
  replacement.count-original.count<=512,Array(replacement.prefix(original.count))==original else{return false}
 let suffix=String(decoding:replacement.dropFirst(original.count),as:UTF16.self)
 return suffix.contains("APW_FOREGROUND_INPUT_SYNTHETIC_V1")
}
func foregroundNoteInputPermits(_ q:[String:Any])->Bool {
 func yes(_ key:String)->Bool {notesProbeForegroundFocusOption(q[key])==true}
 guard let expected=q["expected"] as? [String:Any],let notes=q["notes"] as? String,
  syntheticNotesAppendPermits(expected,notes),let phase=q["phase"] as? String,
  ["selection","replacement"].contains(phase) else{return false}
 return yes("requested") && yes("synthetic_only") && yes("unique_index") && yes("owned_editor") &&
  yes("two_frames") && yes("preimage_exact") && yes("raw_equal") && yes("process_verified") &&
  yes("window_bound") && yes("note_bound") && yes("internal_focus_exact") && yes("observation_complete") &&
  yes("post_access") && yes("physical_modifiers_clear") && !yes("input_attempted") &&
  (phase=="selection" || yes("selection_verified")) &&
  notesProbeForegroundOwnerPermits(original:pid_t(q["original"] as? Int ?? 0),foreground:pid_t(q["foreground"] as? Int ?? 0),passwords:pid_t(q["passwords"] as? Int ?? 0),keyboard:(q["keyboard"] as? Int).map(pid_t.init),deadlineValid:yes("deadline_valid"),internalComplete:yes("observation_complete"),internalBound:yes("internal_focus_exact"))
}
func sameIndexScope(cachedCategory:String,cachedQuery:String,category:String,query:String)->Bool {
 cachedCategory==category && cachedQuery==query
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
// Pure entry-point verification runs before AppKit initializes or any Apple
// process is inspected. The test exercises the same policy used below.
if args==["--policy-test"] {
 guard let line=readLine(),let data=line.data(using:.utf8),let q=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else{exit(2)}
 var result:Any
 switch q["operation"] as? String {
 case "lease":
  result=requestLeaseMode(foreground:pid_t(q["foreground"] as? Int ?? 0),passwords:pid_t(q["passwords"] as? Int ?? 0),keyboard:(q["keyboard"] as? Int).map(pid_t.init),ownedEditor:q["owned_editor"] as? Bool ?? false)
 case "unavailable-context-policy":result=unavailableContextStatus(editor:q["editor"] as? Bool ?? false,incomplete:q["incomplete"] as? Bool ?? false)
 case "query":result=queryStrategy(rangeSettable:q["range_settable"] as? Bool ?? false,textSettable:q["text_settable"] as? Bool ?? false,valueSettable:q["value_settable"] as? Bool ?? false)
 case "witness":result=acceptsSearchWitness(emptySeen:q["empty_seen"] as? Bool ?? false,stableComplete:q["stable_complete"] as? Bool ?? false,ownerUnchanged:q["owner_unchanged"] as? Bool ?? false,count:q["count"] as? Int ?? -1)
 case "recoverable-dialog":result=recoverableDialog(words:q["words"] as? [String] ?? [],ordinaryButton:q["ordinary_button"] as? Bool ?? false,permanentButton:q["permanent_button"] as? Bool ?? false)
 case "selection-scope":result=addressedSelectionScope(role:q["role"] as? String ?? "",identifier:q["identifier"] as? String ?? "",subrole:q["subrole"] as? String ?? "")
 case "query-clear-policy":result=requiresQueryClear(fullIndex:q["full_index"] as? Bool ?? false,queryEmpty:q["query_empty"] as? Bool ?? false)
 case "editor-code-guard":result=recoveryVerificationFieldsSafe(q["roles"] as? [String] ?? [])
 case "notes-write-policy":result=notesWritePermits(role:q["role"] as? String ?? "",rangeCode:q["range_code"] as? Int ?? -1,textCode:q["text_code"] as? Int ?? -1,valueCode:q["value_code"] as? Int ?? -1,rangeSettable:q["range_settable"] as? Bool ?? false,textSettable:q["text_settable"] as? Bool ?? false,twoFrames:q["two_frames"] as? Bool ?? false,fieldsEqual:q["fields_equal"] as? Bool ?? false)
 case "category-caption":result=categoryCaptionMatches(q["value"] as? String ?? "",q["category"] as? String ?? "")
 case "editor-recovery":result=editorRecoveryPermits(expected:q["expected"] as? [String:Any] ?? [:],observed:q["observed"] as? [String:Any] ?? [:],complete:q["complete"] as? Bool ?? false,unique:q["unique"] as? Bool ?? false)
 case "notes-probe-boundary":result=notesProbeBoundaryPermits(expected:q["expected"] as? [String:Any] ?? [:],syntheticOnly:q["synthetic_only"] as? Bool ?? false,count:q["count"] as? Int ?? -1,complete:q["complete"] as? Bool ?? false,stable:q["stable"] as? Bool ?? false,unique:q["unique"] as? Bool ?? false,noEditor:q["no_editor"] as? Bool ?? false,ownerBound:q["owner_bound"] as? Bool ?? false)
 case "notes-probe-outcome":result=notesProbeOutcomePermits(preimageExact:q["preimage_exact"] as? Bool ?? false,diagnosticsComplete:q["diagnostics_complete"] as? Bool ?? false,cancelVerified:q["cancel_verified"] as? Bool ?? false,rereadExact:q["reread_exact"] as? Bool ?? false,finalCancelVerified:q["final_cancel_verified"] as? Bool ?? false)
 case "notes-probe-focus":result=notesProbeFocusMatches(copyCode:q["copy_code"] as? Int ?? -1,pidCode:q["pid_code"] as? Int ?? -1,roleCode:q["role_code"] as? Int ?? -1,samePID:q["same_pid"] as? Bool ?? false,ancestorBound:q["ancestor_bound"] as? Bool ?? false,role:q["role"] as? String ?? "")
 case "notes-probe-foreground-owner":result=notesProbeForegroundOwnerPermits(original:pid_t(q["original"] as? Int ?? 0),foreground:pid_t(q["foreground"] as? Int ?? 0),passwords:pid_t(q["passwords"] as? Int ?? 0),keyboard:(q["keyboard"] as? Int).map(pid_t.init),deadlineValid:q["deadline_valid"] as? Bool ?? false,internalComplete:q["internal_complete"] as? Bool ?? false,internalBound:q["internal_bound"] as? Bool ?? false)
 case "notes-probe-focus-setter":result=notesProbeFocusSetterPermits(requested:q["requested"] as? Bool ?? false,expected:q["expected"] as? [String:Any] ?? [:],ownedEditor:q["owned_editor"] as? Bool ?? false,twoFrames:q["two_frames"] as? Bool ?? false,stateExact:q["state_exact"] as? Bool ?? false,uniqueNote:q["unique_note"] as? Bool ?? false,samePID:q["same_pid"] as? Bool ?? false,completeScope:q["complete_scope"] as? Bool ?? false,identifier:q["identifier"] as? String ?? "",role:q["role"] as? String ?? "",ownerValid:q["owner_valid"] as? Bool ?? false,settableCode:q["settable_code"] as? Int ?? -1,settable:q["settable"] as? Bool ?? false)
 case "notes-probe-error-cleanup":result=notesProbeErrorCleanupPermits(expected:q["expected"] as? [String:Any] ?? [:],first:q["first"] as? [String:Any] ?? [:],second:q["second"] as? [String:Any] ?? [:],complete:q["complete"] as? Bool ?? false,ownedEditor:q["owned_editor"] as? Bool ?? false,ownerValid:q["owner_valid"] as? Bool ?? false,rawEqual:q["raw_equal"] as? Bool ?? false)
 case "notes-probe-focus-option":result=notesProbeForegroundFocusOption(q["value"]).map{$0 ? "true":"false"} ?? "invalid"
 case "notes-probe-read-cleanup":result=notesProbeReadCleanupPolicy(returnedComplete:q["returned_complete"] as? Bool ?? false,openedByRead:q["opened_by_read"] as? Bool ?? false,ownerUnchanged:q["owner_unchanged"] as? Bool ?? false,expectedComplete:q["expected_complete"] as? Bool ?? false,listAvailable:q["list_available"] as? Bool ?? false,inputAttempted:q["input_attempted"] as? Bool ?? false)
 case "foreground-note-input-policy":result=foregroundNoteInputPermits(q)
 case "cache":result=sameIndexScope(cachedCategory:q["cached_category"] as? String ?? "",cachedQuery:q["cached_query"] as? String ?? "",category:q["category"] as? String ?? "",query:q["query"] as? String ?? "")
 default:exit(2)
 }
 let bytes=try! JSONSerialization.data(withJSONObject:["result":result,"apple_accessed":false],options:.sortedKeys)
 print(String(data:bytes,encoding:.utf8)!);exit(0)
}
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
var foregroundNotesProbeWindow:AXUIElement?
var foregroundNotesProbeOriginalPID:pid_t?
var refreshActiveSearchModel=false
var scanActiveList=true
var indexedLabels:[[String]]?
var boundQuery=""
var backgroundUnsafeFocusObserved=false
func attr(_ n:AXUIElement,_ k:String)->CFTypeRef? {
 guard Date()<deadline else{return nil};var v:CFTypeRef?
 let code=AXUIElementCopyAttributeValue(n,k as CFString,&v);observeNativeError(code,required:k==kAXRoleAttribute)
 return code == .success ? v:nil
}
func text(_ n:AXUIElement,_ k:String)->String {attr(n,k) as? String ?? ""}
func nodes(_ root:AXUIElement,prune:Bool=true)->[AXUIElement] {
 var out:[AXUIElement]=[];var seen=Set<UInt>()
 func walk(_ n:AXUIElement,_ depth:Int){
  guard depth<24,out.count<6000,Date()<deadline else{nativeObservationIncomplete=true;return}
  guard seen.insert(CFHash(n)).inserted else{return}
  let r=text(n,kAXRoleAttribute);guard !["AXMenuBar","AXMenu","AXMenuItem"].contains(r) else{return};out.append(n)
  if prune && ["AXOutline","AXTable"].contains(r){return}
  for c in attr(n,kAXChildrenAttribute) as? [AXUIElement] ?? [] {walk(c,depth+1)}
 }
 walk(root,0);return out
}
func values(_ ns:[AXUIElement])->[String] {ns.flatMap{n in [kAXTitleAttribute,kAXDescriptionAttribute,kAXValueAttribute].compactMap{attr(n,$0) as? String}}}
func rowValues(_ row:AXUIElement)->[String] {
 var out:[String]=[],seen=Set<UInt>()
 let names=[kAXRoleAttribute,kAXTitleAttribute,kAXDescriptionAttribute,kAXValueAttribute,kAXChildrenAttribute] as CFArray
 func walk(_ n:AXUIElement,_ depth:Int) {
  guard depth<12,seen.count<100,Date()<deadline else{nativeObservationIncomplete=true;return}
  guard seen.insert(CFHash(n)).inserted else{return}
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
 // A nil system-wide keyboard observation is not a foreign PID. This
 // synthetic-only lease requires positive focus evidence from Passwords
 // itself into the previously verified exact window on every owner check.
 if let window=foregroundNotesProbeWindow,let original=foregroundNotesProbeOriginalPID {
  let root=AXUIElementCreateApplication(appPID)
  let internalBound=completeDiscovery({notesProbeBoundInternalFocus(root,window,editableOnly:false) != nil})==true
  return notesProbeForegroundOwnerPermits(original:original,foreground:NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0,passwords:appPID,keyboard:focusPID(),deadlineValid:Date()<deadline,internalComplete:internalBound,internalBound:internalBound)
 }
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
 let textSelection=[kAXSelectedTextAttribute,kAXSelectedTextRangeAttribute].contains(k) &&
  addressedSelectionScope(role:text(n,kAXRoleAttribute),identifier:text(n,kAXIdentifierAttribute),subrole:text(n,kAXSubroleAttribute))
 guard k != kAXFocusedAttribute,!(backgroundOwnerPID != nil && [kAXSelectedTextAttribute,kAXSelectedTextRangeAttribute].contains(k) && !textSelection),owned(n) else{report["ui_set_foreground_gate_refused"]=true;return false}
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
   set apwRecoverable to false
   set apwPermanentButton to false
   set sheetElements to entire contents of s
   repeat with el in sheetElements
    try
     set apwConfirmRole to value of attribute "AXRole" of el
     set apwConfirmWords to {}
     set apwOrdinaryMatch to false
     try
      set end of apwConfirmWords to value of attribute "AXValue" of el as text
     end try
     try
      set end of apwConfirmWords to value of attribute "AXDescription" of el as text
     end try
     try
      set end of apwConfirmWords to value of attribute "AXTitle" of el as text
     end try
     repeat with apwConfirmWord in apwConfirmWords
      set apwConfirmText to apwConfirmWord as text
      ignoring case
       if apwConfirmText contains "已删除" or apwConfirmText contains "最近删除" or apwConfirmText contains "恢复" or apwConfirmText contains "recently deleted" or apwConfirmText contains "recover" then set apwRecoverable to true
      end ignoring
      if apwConfirmRole is "AXButton" then
       if apwConfirmText is "永久删除" or apwConfirmText is "立即永久删除" or apwConfirmText is "Delete Permanently" or apwConfirmText is "Permanently Delete" then set apwPermanentButton to true
       if apwConfirmText is "删除密码" or apwConfirmText is "删除备注" or apwConfirmText is "删除此密码" or apwConfirmText is "删除" or apwConfirmText is "Delete Password" or apwConfirmText is "Delete Note" or apwConfirmText is "Delete" then set apwOrdinaryMatch to true
      end if
     end repeat
     if apwConfirmRole is "AXButton" and apwOrdinaryMatch then set end of bs to contents of el
    end try
   end repeat
   if (count bs) is not 1 or apwRecoverable is not true or apwPermanentButton then error "ordinary_confirmation_unavailable"
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
func query(_ previous:AXUIElement,_ q:String)->Bool { context(AXUIElementCreateApplication(appPID)).map { text($0.0,kAXValueAttribute)==boundQuery } ?? false }
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
func read(_ root:AXUIElement,_ t:Target,leaveOpen:Bool=false,onEditorOpened:(()->Void)?=nil)->NativeRead? {
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
 let searchQuery=boundQuery
 report["search_identity_kind"]=t.urls.isEmpty ? (searchQuery==t.title ? "exact_title":"bound_companion_title_token"):"bound_website_host"
 guard query(f,searchQuery) else{report["failure_stage"]="single_query_edit";return nil}
 // Filtering may replace the outline object. Reacquire its current model;
 // never use the pre-query AXRows reference as an identity or delete target.
 var observed:[AXUIElement]?,observedLabels:[[String]]?
 let rowLimit=boundQuery.isEmpty ? 3000:100
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
  if let frame=completeDiscovery({()->([AXUIElement],AXUIElement?,AXUIElement?) in
   let frameView=nodes(root)
   var selectedRow:AXUIElement?
   if let (_,list)=context(root),let selectedRows=attr(list,kAXSelectedRowsAttribute) as? [AXUIElement] {
    let own=selectedRows.filter{let labels=rowValues($0);return labels.contains(t.title) && (t.username.isEmpty || labels.contains(t.username))}
    if selectedRows.count==1,own.count==1 {selectedRow=own[0]}
   }
   let detailValues=values(frameView)
   let boundDetail=detailValues.contains(t.title) && (t.notes.isEmpty || detailValues.contains(t.notes)) && (t.username.isEmpty || detailValues.contains(t.username))
   let frameEdit=boundDetail || selectedRow != nil ? button(frameView,["编辑","Edit","编辑密码","Edit Password","编辑备注","Edit Note"]):nil
   return (frameView,selectedRow,frameEdit)
  }) {
   view=frame.0;edit=frame.2
   if let currentRow=frame.1 {row=currentRow;selected=true}
   selected=selected || edit != nil
   if selected,edit != nil {break}
  }
  pause(0.05)
 }
 phase("detail_binding")
 report["selection_context"]=["selected_identity_confirmed":selected,"edit_button_unique":edit != nil]
 let group=sharing(view)
 let detailSnapshot=values(view)
 let boundView=detailSnapshot.contains(t.title) && (t.notes.isEmpty || detailSnapshot.contains(t.notes)) && (t.username.isEmpty || detailSnapshot.contains(t.username))
 guard selected,let edit,boundedClick(edit,root) else{report["failure_stage"]="open_readonly_editor";report["selection_diagnostics"]=selectionDiagnostics(root);return nil}
 let editorUntil=min(deadline,Date(timeIntervalSinceNow:3))
 var opened=false
 while front(),Date()<editorUntil {
  let observed=completeDiscovery {()->Bool in
   let editNodes=nodes(root)
   let editableTitle=editNodes.filter{text($0,kAXIdentifierAttribute)=="TitleField" && ["AXTextField","AXTextArea","AXComboBox"].contains(text($0,kAXRoleAttribute))}
   return editableTitle.count==1 && button(editNodes,["取消","Cancel"]) != nil
  }
  if observed==true {opened=true;onEditorOpened?();break}
  pause(0.03)
 }
 guard opened,!nativeObservationIncomplete else{report["failure_stage"]="editor_open_unverified";return nil}
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
func cancel(_ root:AXUIElement,_ n:NativeRead,actionGuard:(()->Bool)?=nil)->Bool {
 let ns=nodes(root)
 report["cancel_context"]=["foreground":front(),"fields_unchanged":fields(ns)==n.fieldValues,"selected_row":attr(n.row,kAXSelectedAttribute) as? Bool==true,"cancel_button_unique":button(ns,["取消","Cancel"]) != nil]
 guard front(),fields(ns)==n.fieldValues,let b=button(ns,["取消","Cancel"]),actionGuard?() ?? true,boundedClick(b,root) else{return false}
 guard waitForList(root) else{return false}
 if let (ownedRoot,_)=ownEditor,CFEqual(root,ownedRoot) {ownEditor=nil;ownEditorFields=nil;ownNotesProbeExpected=nil;ownNotesProbeCleanupAttempted=false;ownSyntheticInputAttempted=false}
 return true
}
func waitForList(_ root:AXUIElement,seconds:TimeInterval=3)->Bool {
 let until=min(deadline,Date(timeIntervalSinceNow:seconds))
 while front(),Date()<until {
  if completeDiscovery({context(root) != nil})==true {return true}
  pause(0.03)
 }
 return false
}
func apple(_ pid:pid_t)->Bool {var c:SecCode?,r:SecRequirement?;guard SecCodeCopyGuestWithAttributes(nil,[kSecGuestAttributePid as String:pid] as CFDictionary,[],&c)==errSecSuccess,SecRequirementCreateWithString("identifier \"com.apple.Passwords\" and anchor apple" as CFString,[],&r)==errSecSuccess,let c,let r else{return false};return SecCodeCheckValidity(c,[],r)==errSecSuccess}
func ready()->AXUIElement? {
 guard nativeTimeoutSetup == .success else{report["status"]="native_timeout_setup_failed";return nil}
 guard AXIsProcessTrusted(),let a=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Passwords").first,apple(a.processIdentifier) else{report["status"]="native_access_unavailable";return nil}
 appPID=a.processIdentifier;guard front() else{report["status"]="passwords_foreground_required";return nil}
 let root=AXUIElementCreateApplication(appPID);AXUIElementSetMessagingTimeout(root,0.25)
 guard context(root) != nil else{
  let ns=nodes(root),editor=ns.contains{n in ["TitleField","UserNameField","PasswordField","NotesField"].contains(text(n,kAXIdentifierAttribute)) && ["AXTextField","AXTextArea","AXComboBox"].contains(text(n,kAXRoleAttribute))}
  report["status"]=unavailableContextStatus(editor:editor,incomplete:nativeObservationIncomplete)
  return nil
 }
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
func categoryEvidence(_ root:AXUIElement,_ category:String)->(Bool,Int?) {
 let ns=nodes(root),toolbars=ns.filter{text($0,kAXRoleAttribute)=="AXToolbar"}
 let header=toolbars.flatMap{nodes($0)}.filter{text($0,kAXRoleAttribute)=="AXStaticText"}.flatMap{values([$0])}.contains{categoryCaptionMatches($0,category)}
 let names=category=="active" ? ["全部","All"]:["已删除","Deleted","Recently Deleted","最近删除"]
 guard let tile=categoryButton(root,names) else{return (header,nil)}
 var selected=false
 for key in [kAXSelectedAttribute,kAXValueAttribute] {
  if let value=attr(tile,key),CFGetTypeID(value)==CFBooleanGetTypeID(),(value as? Bool)==true {selected=true}
 }
 var labels=values(nodes(tile,prune:false))
 for n in nodes(tile,prune:false) {
  for key in [kAXTitleAttribute,kAXDescriptionAttribute,kAXValueAttribute] {
   if let value=attr(n,key) as? NSAttributedString {labels.append(value.string)}
  }
 }
 var counts=Set<Int>()
 let pattern=try? NSRegularExpression(pattern:"[0-9][0-9,，]*")
 for label in labels {
  for match in pattern?.matches(in:label,range:NSRange(label.startIndex...,in:label)) ?? [] {
   if let range=Range(match.range,in:label),let count=Int(label[range].replacingOccurrences(of:",",with:"").replacingOccurrences(of:"，",with:"")),count<=3000 {counts.insert(count)}
  }
 }
 return (header || selected,counts.count==1 ? counts.first:nil)
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
var indexedCategory=""
var indexedQuery=""
var failedIndexCategories=Set<String>()
var valueSearchAvailable=true
var ownEditor:(AXUIElement,NativeRead)?
var ownEditorFields:[String:String]?
var ownNotesProbeExpected:[String:Any]?
var ownNotesProbeCleanupAttempted=false
// An attempted synthetic event may have changed an editor even when no
// response arrived. Such an editor is retained for explicit review.
var ownSyntheticInputAttempted=false
func acquireRequestLease()throws {
 try require(ownEditor==nil,"owned_editor_requires_review")
 // NSWorkspace delivers activation changes on the run loop. Initialize and
 // drain it before capturing a new request's owner, instead of retaining the
 // owner from the first request for the entire pipe session.
 _=NSWorkspace.shared;pause(0.01)
 if foregroundNotesProbeWindow != nil {
  try require(front(),"passwords_foreground_required")
  backgroundOwnerPID=nil;backgroundUnsafeFocusObserved=false
  report["request_owner_mode"]="foreground";return
 }
 let until=min(deadline,Date(timeIntervalSinceNow:0.4))
 var mode="refuse",foreground:pid_t=0
 repeat {
  foreground=NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
  mode=requestLeaseMode(foreground:foreground,passwords:appPID,keyboard:focusPID(),ownedEditor:false)
  if mode != "refuse" {break};pause(0.02)
 } while Date()<until
 try require(mode != "refuse","owner_unavailable_or_changed")
 backgroundOwnerPID=mode=="background" ? foreground:nil
 backgroundUnsafeFocusObserved=false
 report["request_owner_mode"]=mode
}
func closeOwnEditor() {
 // Save may already have returned to the list when its independent reread
 // fails. Unknown ownership is still an uncertain attempted mutation.
 if ownSyntheticInputAttempted {
  report["synthetic_input_editor_requires_review"]=true
  return
 }
 guard let (root,n)=ownEditor,let expected=ownEditorFields else{return}
 if let probeExpected=ownNotesProbeExpected {
  guard front() else{report["notes_probe_editor_requires_review"]=true;return}
  guard !ownNotesProbeCleanupAttempted else{report["notes_probe_editor_requires_review"]=true;return}
  ownNotesProbeCleanupAttempted=true;report["notes_probe_recovery_attempted"]=true
  do {
   _=try recoverReadonlyEditor(probeExpected,probeOwned:true)
   report["notes_probe_editor_recovered"]=true
  } catch {
   // Keep the editor open for review. Cached websites/shared/OTP/passkey
   // must never authorize Cancel after a whole-state preservation failure.
   report["notes_probe_editor_requires_review"]=true
  }
  return
 }
 guard front() else{return}
 var current=nodes(root)
 guard fields(current)==expected else{return}
 let sheets=current.filter{text($0,kAXRoleAttribute)=="AXSheet"}
 if sheets.count==1,let back=button(nodes(sheets[0]),["取消","Cancel"]),press(back) {pause(0.1);current=nodes(root)}
 guard !current.contains(where:{text($0,kAXRoleAttribute)=="AXSheet"}),fields(current)==expected else{return}
 let observed=NativeRead(row:n.row,fieldValues:expected,editor:current,shared:n.shared,sitesKnown:n.sitesKnown,sites:n.sites,otpAbsent:n.otpAbsent,passkeyAbsent:n.passkeyAbsent,shape:n.shape)
 if cancel(root,observed) {ownEditor=nil;ownEditorFields=nil;ownNotesProbeExpected=nil;ownNotesProbeCleanupAttempted=false}
}
func nativeFailure(_ name:String)->NSError {NSError(domain:"APWMaintenance",code:1,userInfo:[NSLocalizedDescriptionKey:"maintenance_"+name])}
func require(_ ok:Bool,_ name:String)throws {if !ok {throw nativeFailure(name)}}
struct NotesSettableObservation:Equatable {
 let role:String
 let rangeCode,textCode,valueCode:Int
 let rangeSettable,textSettable,valueSettable:Bool
 let actionsCode:Int;let actions:[String]
}
// Capability queries are UI observations too: SwiftUI may invalidate the
// previous NotesField during the editor transition. No setter runs until two
// independent, complete, unchanged frames agree that SelectedText is writable.
func writableNotesField(_ root:AXUIElement,_ n:NativeRead)throws->AXUIElement {
 let requestDeadline=deadline,until=min(deadline,Date(timeIntervalSinceNow:3))
 deadline=until;defer{deadline=requestDeadline}
 var previous:NotesSettableObservation?,stableFrames=0
 let knownActions:Set<String>=["AXConfirm","AXCancel","AXPress","AXShowMenu","AXScrollToVisible","AXRaise","AXIncrement","AXDecrement","AXPick","AXShowAlternateUI","AXShowDefaultUI"]
 while Date()<until,front() {
  let observed=completeDiscovery {()->(AXUIElement,NotesSettableObservation,Bool)? in
   let ns=nodes(root),matches=ns.filter{text($0,kAXIdentifierAttribute)=="NotesField"}
   guard matches.count==1,Date()<until else{return nil}
   let note=matches[0],role=text(note,kAXRoleAttribute),currentFields=fields(ns)
   guard Set(currentFields.keys)==Set(n.fieldValues.keys),["AXTextField","AXTextArea"].contains(role),Date()<until else{return nil}
   let unchanged=currentFields==n.fieldValues
   report["notes_role"]=role
   var rangeWritable=DarwinBoolean(false),textWritable=DarwinBoolean(false),valueWritable=DarwinBoolean(false)
   let rangeCode=AXUIElementIsAttributeSettable(note,kAXSelectedTextRangeAttribute as CFString,&rangeWritable)
   report["notes_range_code"]=rangeCode.rawValue;report["notes_range_settable"]=rangeWritable.boolValue
   observeNativeError(rangeCode,required:rangeCode != .attributeUnsupported)
   guard Date()<until else{return nil}
   let textCode=AXUIElementIsAttributeSettable(note,kAXSelectedTextAttribute as CFString,&textWritable)
   report["notes_text_code"]=textCode.rawValue;report["notes_text_settable"]=textWritable.boolValue
   observeNativeError(textCode,required:textCode != .attributeUnsupported)
   guard Date()<until else{return nil}
   let valueCode=AXUIElementIsAttributeSettable(note,kAXValueAttribute as CFString,&valueWritable)
   report["notes_value_code"]=valueCode.rawValue;report["notes_value_settable"]=valueWritable.boolValue
   observeNativeError(valueCode,required:valueCode != .attributeUnsupported)
   guard Date()<until else{return nil}
   var actionNames:CFArray?
   let actionsCode=AXUIElementCopyActionNames(note,&actionNames)
   observeNativeError(actionsCode,required:actionsCode != .actionUnsupported)
   let rawActions=actionNames as? [String]
   if actionsCode == .success,rawActions==nil {nativeObservationIncomplete=true}
   let actions=(rawActions ?? []).filter{knownActions.contains($0)}.sorted()
   report["notes_action_names"]=actions;report["notes_actions_code"]=actionsCode.rawValue
   let capability=NotesSettableObservation(role:role,rangeCode:Int(rangeCode.rawValue),textCode:Int(textCode.rawValue),valueCode:Int(valueCode.rawValue),rangeSettable:rangeWritable.boolValue,textSettable:textWritable.boolValue,valueSettable:valueWritable.boolValue,actionsCode:Int(actionsCode.rawValue),actions:actions)
   return (note,capability,unchanged)
  }
  if let observed,let frame=observed {
   guard frame.2 else{report["notes_observation_end"]="editable_fields_changed";throw nativeFailure("note_write_refused")}
   stableFrames=frame.1==previous ? stableFrames+1:1;previous=frame.1
   report["notes_observation_frames"]=stableFrames
   if stableFrames>=2,Date()<until,front() {
    let c=frame.1
    if notesWritePermits(role:c.role,rangeCode:c.rangeCode,textCode:c.textCode,valueCode:c.valueCode,rangeSettable:c.rangeSettable,textSettable:c.textSettable,twoFrames:true,fieldsEqual:true) {
     report["notes_observation_end"]="two_complete_writable_frames";return frame.0
    }
    report["notes_observation_end"]="stable_unsupported"
    throw nativeFailure("note_text_replacement_unsupported")
   }
  } else {previous=nil;stableFrames=0;report["notes_observation_frames"]=0}
  pause(0.04)
 }
 report["notes_observation_end"]="transient_or_incomplete_timeout"
 throw nativeFailure("note_text_observation_incomplete")
}
func freshRoot()throws->AXUIElement {
 guard let r=ready() else {
  let reason=report["status"] as? String ?? "locked_or_access_unavailable"
  throw nativeFailure(reason.allSatisfy{$0.isLowercase || $0=="_"} ? reason:"locked_or_access_unavailable")
 }
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
   if expectedID is not "" then
    if (value of attribute "AXIdentifier" of apwElement as text) is not expectedID then error "identity_changed"
   else
    if (value of attribute "\(captionAttribute)" of apwElement as text) is not expectedCaption then error "caption_changed"
   end if
   tell application "System Events" to set apwOwner to unix id of first application process whose frontmost is true
   \(scriptOwnerGuard("apwOwner"))
   click apwElement
  end tell
 end tell
 return "clicked"
 """
 let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/osascript");p.arguments=["-"]
 let input=Pipe(),output=Pipe(),error=Pipe();p.standardInput=input;p.standardOutput=output;p.standardError=error
 do {try p.run();input.fileHandleForWriting.write(Data(source.utf8));try input.fileHandleForWriting.close()}catch{return false}
 let until=Date(timeIntervalSinceNow:8);while p.isRunning,Date()<until {pause(0.02)}
 if p.isRunning {p.terminate();return false}
 let diagnostic=String(data:error.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8) ?? ""
 report["bounded_click_bridge_exit_code"]=p.terminationStatus
 report["bounded_click_bridge_failure"]=["owner_changed","process_changed","window_changed","sheet_changed","role_changed","identity_changed","caption_changed"].first{diagnostic.contains($0)} ?? (p.terminationStatus==0 ? "none":"unclassified_system_events_error")
 if let expression=try? NSRegularExpression(pattern:"\\((-?[0-9]+)\\)"),let match=expression.matches(in:diagnostic,range:NSRange(diagnostic.startIndex...,in:diagnostic)).last,let range=Range(match.range(at:1),in:diagnostic) {report["bounded_click_bridge_error_code"]=Int(diagnostic[range])}
 return p.terminationStatus==0 && front() && String(data:output.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines)=="clicked"
}
func clearSearchQuery(_ root:AXUIElement)->Bool {
 guard let (field,list)=context(root) else{return false}
 let old=text(field,kAXValueAttribute)
 if old.isEmpty {boundQuery="";return !nativeObservationIncomplete}
 guard let before=attr(list,kAXRowsAttribute) as? [AXUIElement] else{return false}
 report["search_clear_before_count"]=before.count
 let known=["取消","Cancel","清除","Clear","清除搜索","Clear Search","取消搜索","Cancel Search","清空搜索"]
 guard let matches=completeDiscovery({nodes(field,prune:false).filter{n in
  text(n,kAXRoleAttribute)=="AXButton" && values([n]).contains{known.contains($0)}
 }}),matches.count==1 else{report["search_clear_failure"]="clear_button_ambiguous";return false}
 guard boundedClick(matches[0],root) else{report["search_clear_failure"]="clear_action_refused";return false}
 let until=min(deadline,Date(timeIntervalSinceNow:4));var lastCount:Int?
 while front(),Date()<until {
  if let observed=completeDiscovery({()->Int? in
   guard let (search,list)=context(root),text(search,kAXValueAttribute).isEmpty,
    let rows=attr(list,kAXRowsAttribute) as? [AXUIElement] else{return nil}
   return rows.count
  }),let count=observed {
   let cached=currentCategory=="deleted" ? deletedLabels?.count:activeLabels?.count
   let evidence=completeDiscovery({categoryEvidence(root,currentCategory)})
   let expected=cached ?? evidence?.1
   report["search_clear_after_count"]=count
   // The cancel action must restore the actual list model, not merely its
   // visible field. A larger list (or known complete cached count) witnesses it.
   if lastCount==count,(count>before.count || expected==count) {
    boundQuery="";indexedLabels=nil;indexedCategory="";indexedQuery=""
    report["search_clear_method"]="addressed_cancel_button";return true
   }
   lastCount=count
  }
  pause(0.05)
 }
 report["search_clear_failure"]="clear_model_unverified";return false
}
func submitQuery(_ root:AXUIElement,_ wanted:String)throws {
 guard let (f,_)=context(root) else{throw nativeFailure("locked_or_user_editor")}
 let owner=NSWorkspace.shared.frontmostApplication?.processIdentifier,keyboard=focusPID()
 var wr=DarwinBoolean(false),wt=DarwinBoolean(false)
 try require(AXUIElementIsAttributeSettable(f,kAXSelectedTextRangeAttribute as CFString,&wr) == .success && wr.boolValue &&
  AXUIElementIsAttributeSettable(f,kAXSelectedTextAttribute as CFString,&wt) == .success && wt.boolValue,"search_text_replacement_unsupported")
 // AXValue can change a visible field without changing its saved model;
 // Confirm is advertised by NSSearchField but refused in the live background
 // trial. Replace the complete addressed text, without focusing or key events.
 var full=CFRange(location:0,length:text(f,kAXValueAttribute).utf16.count)
 guard let range=AXValueCreate(.cfRange,&full),set(f,kAXSelectedTextRangeAttribute,range),let seen=attr(f,kAXSelectedTextRangeAttribute),CFGetTypeID(seen)==AXValueGetTypeID() else{throw nativeFailure("search_selection_unverified")}
 var actual=CFRange();try require(AXValueGetValue(unsafeBitCast(seen,to:AXValue.self),.cfRange,&actual) && actual.location==0 && actual.length==full.length,"search_selection_unverified")
 try require(set(f,kAXSelectedTextAttribute,wanted as CFString),"search_text_replacement_refused")
 report["search_phase"]="selected_text_value_wait"
 let until=min(deadline,Date(timeIntervalSinceNow:4));var valueVerified=false
 while front(),Date()<until {
  if completeDiscovery({()->Bool in
   guard let (fresh,_) = context(root) else{return false}
   return text(fresh,kAXValueAttribute)==wanted
  })==true {valueVerified=true;break}
  pause(0.04)
 }
 try require(NSWorkspace.shared.frontmostApplication?.processIdentifier==owner && focusPID()==keyboard && front(),"search_owner_changed")
 report["search_wait_end"]=valueVerified ? "fresh_target_value_verified":"fresh_target_value_timeout"
 try require(valueVerified,"search_value_changed")
 boundQuery=wanted;indexedLabels=nil
}
func witnessedValueQuery(_ root:AXUIElement,_ wanted:String)throws->[[String]] {
 guard let (field,list)=context(root),let baselineRows=attr(list,kAXRowsAttribute) as? [AXUIElement],!baselineRows.isEmpty else{throw nativeFailure("search_baseline_unverified")}
 var writable=DarwinBoolean(false)
 try require(AXUIElementIsAttributeSettable(field,kAXValueAttribute as CFString,&writable) == .success && writable.boolValue,"search_value_unsupported")
 let owner=NSWorkspace.shared.frontmostApplication?.processIdentifier,keyboard=focusPID()
 let sentinel="apw-no-result-"+UUID().uuidString.lowercased()
 try require(set(field,kAXValueAttribute,sentinel as CFString),"search_value_refused")
 let emptyUntil=min(deadline,Date(timeIntervalSinceNow:3));var emptySeen=false
 while front(),Date()<emptyUntil {
  if let (search,current)=context(root),text(search,kAXValueAttribute)==sentinel,
   let rows=attr(current,kAXRowsAttribute) as? [AXUIElement],rows.isEmpty,!nativeObservationIncomplete {
   pause(0.05)
   if let (again,current)=context(root),text(again,kAXValueAttribute)==sentinel,
    let rows=attr(current,kAXRowsAttribute) as? [AXUIElement],rows.isEmpty,!nativeObservationIncomplete {emptySeen=true;break}
  }
  pause(0.03)
 }
 try require(emptySeen,"search_empty_witness_unverified")
 guard let (current,_) = context(root) else{throw nativeFailure("search_context_changed")}
 try require(set(current,kAXValueAttribute,wanted as CFString),"search_value_refused")
 let until=min(deadline,Date(timeIntervalSinceNow:4))
 while front(),Date()<until {
  if let (search,list)=context(root),text(search,kAXValueAttribute)==wanted,
   let rows=attr(list,kAXRowsAttribute) as? [AXUIElement],rows.count<=100,!rows.isEmpty,
   let labels=completeDiscovery({rows.map{rowValues($0)}}),labels.contains(where:{$0.contains(wanted)}) {
   pause(0.07)
   if let (fresh,list)=context(root),text(fresh,kAXValueAttribute)==wanted,
    let rows=attr(list,kAXRowsAttribute) as? [AXUIElement],rows.count<=100,
    let stable=completeDiscovery({rows.map{rowValues($0)}}),stable==labels,
    acceptsSearchWitness(emptySeen:emptySeen,stableComplete:true,ownerUnchanged:NSWorkspace.shared.frontmostApplication?.processIdentifier==owner && focusPID()==keyboard,count:stable.count) {
    boundQuery=wanted;indexedLabels=stable
    report["search_empty_witness_verified"]=true;return stable
   }
  }
  pause(0.03)
 }
 // A zero target list could still be the sentinel model. Never call that
 // item_not_found: only a complete All index can prove absence in this case.
 throw nativeFailure("search_target_model_unverified")
}
func selectCategory(_ root:AXUIElement,_ category:String,buildIndex:Bool=true)throws {
 guard let contextFrame=completeDiscovery({context(root)}),contextFrame != nil else{throw nativeFailure("locked_or_user_editor")}
 let previousEvidence=completeDiscovery({categoryEvidence(root,category)})
 if currentCategory != category || previousEvidence?.0 != true {
  let names=category=="active" ? ["全部","All"]:["已删除","Deleted","Recently Deleted","最近删除"]
  guard let b=categoryButton(root,names) else{throw nativeFailure("category_ambiguous")}
  try require(boundedClick(b,root),"category_selection_failed")
  let until=min(deadline,Date(timeIntervalSinceNow:3));var verified=false
  while front(),Date()<until {
   if completeDiscovery({categoryEvidence(root,category).0})==true {verified=true;break}
   pause(0.04)
  }
  report["search_phase"]="category_confirmation"
  report["search_wait_end"]=verified ? "category_verified":"category_unverified"
  try require(verified,"category_selection_unverified");currentCategory=category
 }
 if !buildIndex {return}
 guard let (currentSearch,_)=context(root) else{throw nativeFailure("locked_or_user_editor")}
 if requiresQueryClear(fullIndex:buildIndex,queryEmpty:text(currentSearch,kAXValueAttribute).isEmpty) {
  try require(clearSearchQuery(root),"list_preparation_failed");boundQuery=""
 }
 try require(context(root).map{text($0.0,kAXValueAttribute).isEmpty} ?? false,"filtered_list_refused")
 boundQuery=""
 guard let (_,list)=context(root),let rows=attr(list,kAXRowsAttribute) as? [AXUIElement],rows.count<=3000 else{throw nativeFailure("list_unavailable")}
 let cached=category=="active" ? activeLabels:deletedLabels
 if let cached {
  try require(cached.count==rows.count,"index_generation_changed");indexedLabels=cached
 } else {
  try require(!failedIndexCategories.contains(category),"prior_incomplete_index_requires_review")
  failedIndexCategories.insert(category)
  guard let labels=completeDiscovery({rows.map{rowValues($0)}}) else{throw nativeFailure("incomplete_discovery_snapshot")}
  if category=="active" {activeLabels=labels}else{deletedLabels=labels};indexedLabels=labels
  failedIndexCategories.remove(category)
 }
 indexedCategory=category;indexedQuery=""
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
func readKey(_ key:[String:String],_ category:String="active",leaveOpen:Bool=false,guardedExpected:[String:Any]?=nil)throws->(AXUIElement,NativeRead,[String:Any]) {
 let root=try freshRoot();try selectCategory(root,category,buildIndex:false)
 guard let title=key["title"],!title.isEmpty,let user=key["username"] else{throw nativeFailure("identity_invalid")}
 guard let (search,_) = context(root) else{throw nativeFailure("locked_or_user_editor")}
 var rangeSettable=DarwinBoolean(false),textSettable=DarwinBoolean(false),valueSettable=DarwinBoolean(false)
 let rangeSupported=AXUIElementIsAttributeSettable(search,kAXSelectedTextRangeAttribute as CFString,&rangeSettable) == .success && rangeSettable.boolValue
 let textSupported=AXUIElementIsAttributeSettable(search,kAXSelectedTextAttribute as CFString,&textSettable) == .success && textSettable.boolValue
 let valueSupported=valueSearchAvailable && AXUIElementIsAttributeSettable(search,kAXValueAttribute as CFString,&valueSettable) == .success && valueSettable.boolValue
 var strategy=queryStrategy(rangeSettable:rangeSupported,textSettable:textSupported,valueSettable:valueSupported)
 report["search_strategy"]=strategy
 if strategy=="witnessed-value" {
  let previousIncomplete=nativeObservationIncomplete
  do {
   nativeObservationIncomplete=false
   let labels=try witnessedValueQuery(root,title)
   try require(!nativeObservationIncomplete,"search_observation_incomplete")
   indexedLabels=labels;indexedCategory=category;indexedQuery=title
  } catch {
   // No account field has been touched. Discard this search observation and
   // require a separately complete, unfiltered discovery instead.
   valueSearchAvailable=false;strategy="unfiltered-index"
   report["search_strategy"]=strategy
   report["search_witness_failure"]=(error as NSError).localizedDescription
  }
  nativeObservationIncomplete=previousIncomplete
 }
 if strategy=="unfiltered-index" {
  // The search field's selected-text attributes are not writable on every
  // macOS release. Reuse one complete category index in this helper session.
  // Never infer uniqueness from a partial index, and never scan per record.
  guard let (freshSearch,_) = context(root) else{throw nativeFailure("locked_or_user_editor")}
  if !text(freshSearch,kAXValueAttribute).isEmpty {
   try require(clearSearchQuery(root),"list_preparation_failed")
  }
  try selectCategory(root,category,buildIndex:true)
 } else if strategy=="selected-text" {
 try submitQuery(root,title)
 report["search_phase"]="bounded_model_wait"
 let until=Date(timeIntervalSinceNow:4);var labels:[[String]]?
 while front(),Date()<until {
  if let observed=completeDiscovery({()->[[String]]? in
   guard let (search,list)=context(root),text(search,kAXValueAttribute)==title,
    let rows=attr(list,kAXRowsAttribute) as? [AXUIElement],rows.count<=100 else{return nil}
   report["search_result_count"]=rows.count
   return rows.map{rowValues($0)}
  }),let current=observed {
   if current.contains(where:{$0.contains(title)}) {labels=current;break}
  }
  pause(0.05)
 }
 if let labels {
  pause(0.06)
  let stable=completeDiscovery {()->[[String]]? in
   guard let (search,list)=context(root),text(search,kAXValueAttribute)==title,
    let rows=attr(list,kAXRowsAttribute) as? [AXUIElement],rows.count<=100 else{return nil}
   return rows.map{rowValues($0)}
  }
  guard front(),stable != nil,stable! == labels else{throw nativeFailure("bounded_search_generation_changed")}
  indexedLabels=labels;indexedCategory=category;indexedQuery=title
  report["search_wait_end"]="bounded_exact_model_verified"
 } else {
  // A stale empty result after a model transition cannot prove absence.
  // Establish an independently complete category index for that proof.
  report["search_wait_end"]="bounded_target_missing_using_complete_index"
  try selectCategory(root,category,buildIndex:true)
 }
 }
 guard sameIndexScope(cachedCategory:indexedCategory,cachedQuery:indexedQuery,category:category,query:boundQuery),let labels=indexedLabels else{throw nativeFailure("index_scope_changed")}
 let matches=labels.filter{$0.contains(title) && (user.isEmpty || $0.contains(user))}
 try require(matches.count>0,"item_not_found");try require(matches.count==1,"item_ambiguous")
 let target=Target(title:title,native_title:title,username:user,notes:"",urls:[])
 let n:NativeRead
 if let expected=guardedExpected {
  // Identity still comes from this exact query/complete-index path. The
  // ownership helper only ensures a partial editor read cannot be blindly
  // canceled using cached metadata; it grants no cohort/index permission.
  n=try ownedNotesProbeRead(root,target,expected)
 } else {
  guard let observed=read(root,target,leaveOpen:true) else {
   let stage=report["failure_stage"] as? String ?? "unknown"
   throw nativeFailure("native_read_"+(stage.allSatisfy({$0.isLowercase || $0=="_"}) ? stage:"unknown"))
  }
  n=observed
 }
 ownEditor=(root,n);ownEditorFields=n.fieldValues
 let value:[String:Any]
 do {value=try snapshot(key,n)} catch {if guardedExpected==nil {_=cancel(root,n)};throw error}
 if !leaveOpen {try require(cancel(root,n),"editor_cancel_unverified");ownEditor=nil;ownEditorFields=nil;ownNotesProbeExpected=nil;ownNotesProbeCleanupAttempted=false}
 return (root,n,value)
}
func equalState(_ a:[String:Any],_ b:[String:Any])->Bool {NSDictionary(dictionary:a).isEqual(to:b)}
func observeReadonlyEditor(_ root:AXUIElement,_ key:[String:String])throws->(NativeRead,[String:Any]) {
 let prior=nativeObservationIncomplete;nativeObservationIncomplete=false
 defer{nativeObservationIncomplete=prior}
 try require(front(),"owner_changed")
 let ns=nodes(root),windows=ns.filter{text($0,kAXSubroleAttribute)=="AXStandardWindow"}
 try require(windows.count==1 && !ns.contains{text($0,kAXRoleAttribute)=="AXSheet"},"editor_recovery_context_ambiguous")
 for id in ["TitleField","UserNameField","PasswordField","NotesField"] {
  let matches=ns.filter{text($0,kAXIdentifierAttribute)==id && ["AXTextField","AXTextArea","AXComboBox"].contains(text($0,kAXRoleAttribute))}
  try require(matches.count==1,"editor_recovery_fields_ambiguous")
 }
 // Editable OTP seed values are not in the current state/journal schema.
 // Never discard one based only on the lossy unknown/absent OTP status.
 let verificationRoles=ns.filter{text($0,kAXIdentifierAttribute)=="VerificationCodeField"}.map{text($0,kAXRoleAttribute)}
 try require(recoveryVerificationFieldsSafe(verificationRoles),"editor_recovery_verification_seed_unmodeled")
 try require(button(ns,["取消","Cancel"]) != nil,"editor_recovery_context_ambiguous")
 let form=formNodes(ns),fs=fields(ns),sites=websites(ns)
 try require(!form.isEmpty && sites.0,"editor_recovery_snapshot_incomplete")
 let setupNames=["设置密钥","Set Up Key","设置密钥…","Set Up Key…","设置密钥...","Set Up Key...","设置验证码","Set Up Verification Code","设置验证码…","Set Up Verification Code…","设置验证码...","Set Up Verification Code...","添加验证码","Add Verification Code","添加验证码…","Add Verification Code…"]
 let setupButtons=form.filter{text($0,kAXRoleAttribute)=="AXButton" && values([$0]).contains{setupNames.contains($0)}}
 let codeLabels=form.filter{text($0,kAXIdentifierAttribute)=="VerificationCodeField"}
 let noOTP=codeLabels.count==1 && text(codeLabels[0],kAXRoleAttribute)=="AXStaticText" && setupButtons.count==1
 let forbidden=form.filter{["AXButton","AXStaticText","AXLink"].contains(text($0,kAXRoleAttribute)) && !["NotesField","TitleField","UserNameField","PasswordField"].contains(text($0,kAXIdentifierAttribute))}.flatMap{values([$0])}.contains{s in
  let lower=s.lowercased();return (s.contains("通行密钥") || lower.contains("passkey")) && !s.contains("添加通行密钥") && !lower.contains("add passkey") && !s.contains("进一步了解") && !lower.contains("learn more")
 }
 let n=NativeRead(row:root,fieldValues:fs,editor:ns,shared:sharing(ns),sitesKnown:sites.0,sites:sites.1,otpAbsent:noOTP,
  passkeyAbsent:!form.isEmpty && sites.0 && sites.1.isEmpty && key["username"]=="" && !forbidden,shape:[:])
 let state=try snapshot(key,n)
 try require(!nativeObservationIncomplete,"editor_recovery_snapshot_incomplete")
 return (n,state)
}
func recoverReadonlyEditor(_ expected:[String:Any],ownerGuard:(()->Bool)?=nil,probeOwned:Bool=false)throws->[String:Any] {
 guard let key=expected["key"] as? [String:String],editorRecoveryPermits(expected:expected,observed:expected,complete:true,unique:true) else{throw nativeFailure("editor_recovery_snapshot_invalid")}
 let root=AXUIElementCreateApplication(appPID);AXUIElementSetMessagingTimeout(root,0.25)
 try require(ownerGuard?() ?? true,"editor_recovery_owner_changed")
 let first=try observeReadonlyEditor(root,key)
 try require(editorRecoveryPermits(expected:expected,observed:first.1,complete:true,unique:true),"editor_recovery_state_changed")
 pause(0.08)
 try require(ownerGuard?() ?? true,"editor_recovery_owner_changed")
 let second=try observeReadonlyEditor(root,key)
 try require(editorRecoveryPermits(expected:expected,observed:second.1,complete:true,unique:true),"editor_recovery_state_changed")
 if probeOwned {
  let owned=ownEditor.map{CFEqual($0.0,root)} ?? false
  try require(notesProbeErrorCleanupPermits(expected:expected,first:first.1,second:second.1,complete:true,ownedEditor:owned,ownerValid:front() && (ownerGuard?() ?? true),rawEqual:first.0.fieldValues==ownEditorFields && second.0.fieldValues==ownEditorFields),"editor_recovery_state_changed")
 }
 ownEditor=(root,second.0);ownEditorFields=second.0.fieldValues
 try require(cancel(root,second.0,actionGuard:ownerGuard),"editor_recovery_cancel_unverified")
 try require(ownerGuard?() ?? true,"editor_recovery_owner_changed")
 return ["ok":true,"recovered":true,"credentials_changed":0,"imports":0,"exports":0,"journal_modified":false]
}
struct NotesProbeCohort:Equatable {let query:String;let labels:[[String]]}
// Current-cohort diagnosis only: no query/category setter or global index.
func currentNotesProbeCohort(_ root:AXUIElement,_ expected:[String:Any],original:NotesProbeCohort?=nil)throws->NotesProbeCohort {
 let key=expected["key"] as! [String:String],title=key["title"]!,user=key["username"]!
 let until=min(deadline,Date(timeIntervalSinceNow:3));var previous:NotesProbeCohort?
 while Date()<until,front() {
  if let observed=completeDiscovery({()->NotesProbeCohort? in
   guard let (search,list)=context(root),let rows=attr(list,kAXRowsAttribute) as? [AXUIElement] else{return nil}
   report["notes_probe_row_count"]=rows.count
   guard rows.count>0,rows.count<=100,let query=attr(search,kAXValueAttribute) as? String else{return nil}
   return NotesProbeCohort(query:query,labels:rows.map{rowValues($0)})
  }),let cohort=observed {
   if let original {try require(cohort==original,"notes_probe_cohort_changed")}
   let matches=cohort.labels.filter{$0.contains(title) && (user.isEmpty || $0.contains(user))}
   try require(matches.count==1,"notes_probe_cohort_identity_unverified")
   if cohort==previous,notesProbeBoundaryPermits(expected:expected,syntheticOnly:true,count:cohort.labels.count,complete:true,stable:true,unique:true,noEditor:true,ownerBound:front()) {return cohort}
   previous=cohort
  } else {previous=nil}
  pause(0.04)
 }
 throw nativeFailure("notes_probe_cohort_incomplete")
}
func bindNotesProbeCohort(_ cohort:NotesProbeCohort) {
 indexedLabels=cohort.labels;indexedCategory="diagnostic-cohort";indexedQuery=cohort.query;boundQuery=cohort.query
}
let notesProbeRoles:Set<String>=["AXTextField","AXTextArea","AXComboBox","AXStaticText","AXGroup","AXScrollArea","AXButton","AXImage","AXLink","AXCheckBox","AXRadioButton","AXPopUpButton","AXOutline","AXTable","AXRow","AXToolbar","AXWindow","AXApplication"]
func notesProbeAncestorBound(_ element:AXUIElement,_ note:AXUIElement)->Bool {
 var current=element;var seen=Set<UInt>()
 for _ in 0..<8 {
  guard Date()<deadline,seen.insert(CFHash(current)).inserted else{return false}
  var pid:pid_t=0
  guard AXUIElementGetPid(current,&pid) == .success,pid==appPID else{return false}
  if CFEqual(current,note) {return true}
  var parent:CFTypeRef?
  guard AXUIElementCopyAttributeValue(current,kAXParentAttribute as CFString,&parent) == .success,let parent,CFGetTypeID(parent)==AXUIElementGetTypeID() else{return false}
  current=unsafeBitCast(parent,to:AXUIElement.self)
 }
 return false
}
func notesProbeBoundInternalFocus(_ root:AXUIElement,_ ancestor:AXUIElement,editableOnly:Bool)->AXUIElement? {
 guard Date()<deadline else{return nil}
 var ancestorPID:pid_t=0
 let ancestorPIDCode=AXUIElementGetPid(ancestor,&ancestorPID);observeNativeError(ancestorPIDCode,required:true)
 guard ancestorPIDCode == .success,ancestorPID==appPID else{return nil}
 var value:CFTypeRef?
 let copyCode=AXUIElementCopyAttributeValue(root,kAXFocusedUIElementAttribute as CFString,&value);observeNativeError(copyCode,required:true)
 guard copyCode == .success,let value,CFGetTypeID(value)==AXUIElementGetTypeID() else{return nil}
 let focused=unsafeBitCast(value,to:AXUIElement.self);var current=focused,seen=Set<UInt>()
 var roleValue:CFTypeRef?
 let roleCode=AXUIElementCopyAttributeValue(focused,kAXRoleAttribute as CFString,&roleValue);observeNativeError(roleCode,required:true)
 guard roleCode == .success,let role=roleValue as? String,notesProbeRoles.contains(role),
  !editableOnly || ["AXTextField","AXTextArea","AXComboBox"].contains(role) else{return nil}
 for _ in 0..<16 {
  guard Date()<deadline,seen.insert(CFHash(current)).inserted else{return nil}
  var pid:pid_t=0
  let pidCode=AXUIElementGetPid(current,&pid);observeNativeError(pidCode,required:true)
  guard pidCode == .success,pid==appPID else{return nil}
  if CFEqual(current,ancestor) {return focused}
  var parent:CFTypeRef?
  let parentCode=AXUIElementCopyAttributeValue(current,kAXParentAttribute as CFString,&parent);observeNativeError(parentCode,required:true)
  guard parentCode == .success,let parent,CFGetTypeID(parent)==AXUIElementGetTypeID() else{return nil}
  current=unsafeBitCast(parent,to:AXUIElement.self)
 }
 return nil
}
func beginForegroundNotesProbeLease()throws {
 report["notes_probe_stage"]="foreground_owner"
 _=NSWorkspace.shared;pause(0.01)
 let original=NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0,keyboard=focusPID()
 try require(original==appPID && appPID>0 && (keyboard==nil || keyboard==appPID),"passwords_foreground_required")
 let root=AXUIElementCreateApplication(appPID)
 let discovered=completeDiscovery {()->AXUIElement? in
  var value:CFTypeRef?
  let code=AXUIElementCopyAttributeValue(root,kAXWindowsAttribute as CFString,&value);observeNativeError(code,required:true)
  guard code == .success,let windows=value as? [AXUIElement],windows.count==1 else{return nil}
  let window=windows[0]
  guard text(window,kAXRoleAttribute)=="AXWindow",text(window,kAXSubroleAttribute)=="AXStandardWindow",
   notesProbeBoundInternalFocus(root,window,editableOnly:false) != nil else{return nil}
  return window
 }
 guard let window=discovered ?? nil else{throw nativeFailure("notes_probe_foreground_owner_unverified")}
 let currentKeyboard=focusPID()
 try require(NSWorkspace.shared.frontmostApplication?.processIdentifier==original && (currentKeyboard==nil || currentKeyboard==appPID),"passwords_foreground_required")
 foregroundNotesProbeWindow=window;foregroundNotesProbeOriginalPID=original
 try require(front(),"notes_probe_foreground_owner_unverified")
}
func notesProbeCurrentNote(_ frame:NativeRead)->AXUIElement? {
 let observed=completeDiscovery {()->AXUIElement? in
  let matches=frame.editor.filter{text($0,kAXIdentifierAttribute)=="NotesField"}
  guard matches.count==1 else{return nil}
  let note=matches[0],role=text(note,kAXRoleAttribute)
  var pid:pid_t=0
  let code=AXUIElementGetPid(note,&pid);observeNativeError(code,required:true)
  guard code == .success,pid==appPID,["AXTextField","AXTextArea"].contains(role) else{return nil}
  return note
 }
 return observed ?? nil
}
// The only AXFocused setter in the helper. It is synthetic-only, one-shot,
// and does not go through or weaken the generic set() prohibition.
func rawSetNotesProbeFocus(_ root:AXUIElement,_ expected:[String:Any],_ key:[String:String])throws {
 try require(report["focus_requested"] as? Bool==true && foregroundNotesProbeWindow != nil && front(),"notes_probe_focus_scope_unverified")
 guard let (ownedRoot,ownedRead)=ownEditor,CFEqual(root,ownedRoot),ownEditorFields==ownedRead.fieldValues else{throw nativeFailure("notes_probe_focus_scope_unverified")}
 let first=try observeReadonlyEditor(root,key)
 try require(equalState(first.1,expected) && first.0.fieldValues==ownedRead.fieldValues,"notes_probe_preimage_changed")
 pause(0.04)
 let second=try observeReadonlyEditor(root,key)
 try require(equalState(second.1,expected) && second.0.fieldValues==ownedRead.fieldValues,"notes_probe_preimage_changed")
 guard let firstNote=notesProbeCurrentNote(first.0),let note=notesProbeCurrentNote(second.0),CFEqual(firstNote,note) else{throw nativeFailure("notes_probe_focus_scope_unverified")}
 let scope=completeDiscovery {()->(String,String,Bool,AXError,Bool)? in
  let role=text(note,kAXRoleAttribute),identifier=text(note,kAXIdentifierAttribute)
  var pid:pid_t=0,writable=DarwinBoolean(false)
  let pidCode=AXUIElementGetPid(note,&pid);observeNativeError(pidCode,required:true)
  let code=AXUIElementIsAttributeSettable(note,kAXFocusedAttribute as CFString,&writable)
  observeNativeError(code,required:code != .attributeUnsupported)
  report["focus_settable"]=code == .success && writable.boolValue
  return (role,identifier,pidCode == .success && pid==appPID,code,writable.boolValue)
 }
 guard let observed=scope ?? nil else{throw nativeFailure("notes_probe_focus_observation_incomplete")}
 try require(notesProbeFocusSetterPermits(requested:report["focus_requested"] as? Bool==true,expected:expected,ownedEditor:ownEditor != nil,twoFrames:true,stateExact:true,uniqueNote:true,samePID:observed.2,completeScope:true,identifier:observed.1,role:observed.0,ownerValid:front(),settableCode:Int(observed.3.rawValue),settable:observed.4),"notes_probe_focus_unsupported_or_unverified")
 // Recheck the exact owned frame and positive app-internal focus immediately
 // before sending one addressed focus request. Never retry this setter.
 let final=try observeReadonlyEditor(root,key)
 guard let finalNote=notesProbeCurrentNote(final.0) else{throw nativeFailure("notes_probe_focus_scope_unverified")}
 try require(equalState(final.1,expected) && final.0.fieldValues==ownedRead.fieldValues &&
  CFEqual(finalNote,note) && front(),"notes_probe_focus_scope_unverified")
 let code=AXUIElementSetAttributeValue(note,kAXFocusedAttribute as CFString,kCFBooleanTrue)
 report["focus_set_code"]=code.rawValue
 try require(code == .success,"notes_probe_focus_set_failed")
 let until=min(deadline,Date(timeIntervalSinceNow:3));var previousFocus:AXUIElement?
 while Date()<until,front() {
  let frame=try observeReadonlyEditor(root,key)
  try require(equalState(frame.1,expected) && frame.0.fieldValues==ownedRead.fieldValues,"notes_probe_preimage_changed")
  if let observed=completeDiscovery({()->AXUIElement? in
   guard let currentNote=notesProbeCurrentNote(frame.0),CFEqual(currentNote,note) else{return nil}
   return notesProbeBoundInternalFocus(root,currentNote,editableOnly:true)
  }),let focused=observed {
   if let previousFocus,CFEqual(previousFocus,focused),front() {report["focus_verified"]=true;return}
   previousFocus=focused
  } else {previousFocus=nil}
  pause(0.04)
 }
 throw nativeFailure("notes_probe_focus_unverified")
}
func notesProbeInternalFocus(_ root:AXUIElement,_ note:AXUIElement)->[String:Any] {
 var value:CFTypeRef?
 let code=AXUIElementCopyAttributeValue(root,kAXFocusedUIElementAttribute as CFString,&value)
 var result:[String:Any]=["code":code.rawValue,"same_pid":false,"matches_notes":false,"known_role":"none"]
 guard code == .success,let value,CFGetTypeID(value)==AXUIElementGetTypeID() else{return result}
 let focused=unsafeBitCast(value,to:AXUIElement.self);var pid:pid_t=0;var roleValue:CFTypeRef?
 let pidCode=AXUIElementGetPid(focused,&pid),roleCode=AXUIElementCopyAttributeValue(focused,kAXRoleAttribute as CFString,&roleValue)
 let role=roleValue as? String ?? "",samePID=pidCode == .success && pid==appPID
 result["same_pid"]=samePID
 result["known_role"]=roleCode == .success ? (notesProbeRoles.contains(role) ? role:"other"):"none"
 result["matches_notes"]=notesProbeFocusMatches(copyCode:Int(code.rawValue),pidCode:Int(pidCode.rawValue),roleCode:Int(roleCode.rawValue),samePID:samePID,ancestorBound:samePID && notesProbeAncestorBound(focused,note),role:role)
 return result
}
func notesProbeChildren(_ note:AXUIElement)->[String:Any]? {
 var seen=Set<UInt>(),children:[[String:Any]]=[]
 func walk(_ element:AXUIElement,_ depth:Int)->Bool {
  guard Date()<deadline,seen.insert(CFHash(element)).inserted else{return false}
  var childValue:CFTypeRef?
  let code=AXUIElementCopyAttributeValue(element,kAXChildrenAttribute as CFString,&childValue)
  if [.attributeUnsupported,.noValue].contains(code) {return true}
  observeNativeError(code,required:true)
  guard code == .success,let nodes=childValue as? [AXUIElement] else{return false}
  guard nodes.isEmpty || depth<4,children.count+nodes.count<=16 else{return false}
  for child in nodes {
   var pid:pid_t=0
   let pidCode=AXUIElementGetPid(child,&pid);observeNativeError(pidCode,required:true)
   let samePID=pidCode == .success && pid==appPID,parentBound=samePID && notesProbeAncestorBound(child,note)
   let role=text(child,kAXRoleAttribute),identifier=text(child,kAXIdentifierAttribute)
   guard samePID,parentBound,!role.isEmpty else{return false}
   children.append(["role":notesProbeRoles.contains(role) ? role:"other","depth":depth+1,"identifier_present":!identifier.isEmpty,"same_pid":samePID,"parent_bound":parentBound,"editable_role":["AXTextField","AXTextArea","AXComboBox"].contains(role)])
   if !walk(child,depth+1) {return false}
  }
  return true
 }
 guard walk(note,0) else{return nil}
 return ["count":children.count,"complete":true,"nodes":children]
}
func notesProbeStructure(_ root:AXUIElement,_ fieldsBefore:[String:String])throws {
 let until=min(deadline,Date(timeIntervalSinceNow:3));var previous:[String:Any]?
 while Date()<until,front() {
  if let observed=completeDiscovery({()->[String:Any]? in
   let ns=nodes(root),matches=ns.filter{text($0,kAXIdentifierAttribute)=="NotesField"}
   guard matches.count==1,fields(ns)==fieldsBefore,let children=notesProbeChildren(matches[0]) else{return nil}
   return ["notes_children":children,"notes_internal_focus":notesProbeInternalFocus(root,matches[0])]
  }),let structure=observed {
   if let previous,NSDictionary(dictionary:previous).isEqual(to:structure),front() {
    report["notes_children"]=structure["notes_children"];report["notes_internal_focus"]=structure["notes_internal_focus"];return
   }
   previous=structure
  } else {previous=nil}
  pause(0.04)
 }
 throw nativeFailure("notes_probe_structure_incomplete")
}
func ownedNotesProbeRead(_ root:AXUIElement,_ target:Target,_ expected:[String:Any])throws->NativeRead {
 try require(ownEditor==nil,"editor_requires_review")
 let foregroundBefore=NSWorkspace.shared.frontmostApplication?.processIdentifier,keyboardBefore=focusPID()
 var openedByRead=false
 let observed=read(root,target,leaveOpen:true,onEditorOpened:{openedByRead=true})
 report["notes_probe_read_opened"]=openedByRead
 let complete=observed.map{n in !nativeObservationIncomplete && n.sitesKnown && ["TitleField","UserNameField","PasswordField","NotesField"].allSatisfy{n.fieldValues[$0] != nil}} ?? false
 func originalOwnerUnchanged()->Bool {
  foregroundBefore != nil && (keyboardBefore != nil || foregroundNotesProbeWindow != nil) && NSWorkspace.shared.frontmostApplication?.processIdentifier==foregroundBefore && focusPID()==keyboardBefore && front()
 }
 let expectedComplete=editorRecoveryPermits(expected:expected,observed:expected,complete:true,unique:true)
 let initialPolicy=notesProbeReadCleanupPolicy(returnedComplete:complete,openedByRead:openedByRead,ownerUnchanged:originalOwnerUnchanged(),expectedComplete:expectedComplete,listAvailable:false,inputAttempted:ownSyntheticInputAttempted)
 if initialPolicy=="register_before_snapshot",let observed {
  // The exact complete editor belongs to this read before snapshot() can
  // throw. Existing readonly cleanup can now close it only if unchanged.
  ownEditor=(root,observed);ownEditorFields=observed.fieldValues
  ownNotesProbeExpected=expected;ownNotesProbeCleanupAttempted=false
  return observed
 }
 if initialPolicy=="requires_review",ownSyntheticInputAttempted {
  // A partial post-input read is not a new readonly recovery permission.
  // Preserve any exact editor provenance actually returned by this read;
  // never fabricate complete state or cancel from cached metadata.
  if openedByRead,let observed {
   ownEditor=(root,observed);ownEditorFields=observed.fieldValues
   ownNotesProbeExpected=expected
  }
  report["synthetic_input_editor_requires_review"]=true
  throw nativeFailure("editor_requires_review")
 }
 let listAvailable=completeDiscovery({context(root) != nil})==true
 let policy=notesProbeReadCleanupPolicy(returnedComplete:complete,openedByRead:openedByRead,ownerUnchanged:originalOwnerUnchanged(),expectedComplete:expectedComplete,listAvailable:listAvailable)
 if policy=="recover_expected_once" {
  report["notes_probe_recovery_attempted"]=true
  do {
   _=try recoverReadonlyEditor(expected,ownerGuard:originalOwnerUnchanged)
   report["notes_probe_editor_recovered"]=true
  } catch {
   // Recovery already attempted its own guarded Cancel. Do not let the
   // outer generic cleanup blindly retry that action on this failure.
   ownEditor=nil;ownEditorFields=nil;ownNotesProbeExpected=nil;ownNotesProbeCleanupAttempted=false
   report["notes_probe_editor_requires_review"]=true
   throw nativeFailure("editor_requires_review")
  }
  throw nativeFailure("notes_probe_read_incomplete")
 }
 if policy=="no_owned_editor" {throw nativeFailure("notes_probe_read_incomplete")}
 report["notes_probe_editor_requires_review"]=true
 throw nativeFailure("editor_requires_review")
}
func notesEditorProbe(_ expected:[String:Any],_ key:[String:String],foregroundFocus:Bool=false)throws->[String:Any] {
 // read() uses this temporary cohort to revalidate a current exact row.
 // It must never remain available as a global mutation/index permission.
 defer{indexedLabels=nil;indexedCategory="";indexedQuery="";boundQuery=""}
 let root=try freshRoot()
 report["notes_probe_stage"]="initial_cohort"
 let cohort=try currentNotesProbeCohort(root,expected);bindNotesProbeCohort(cohort)
 let target=Target(title:key["title"]!,native_title:expected["native_title"] as! String,username:key["username"]!,notes:"",urls:[])
 report["notes_probe_stage"]="initial_read"
 let first=try ownedNotesProbeRead(root,target,expected)
 let state=try snapshot(key,first)
 report["notes_probe_stage"]="initial_state"
 try require(equalState(state,expected),"notes_probe_preimage_changed")
 let firstFrame=try observeReadonlyEditor(root,key)
 try require(equalState(firstFrame.1,expected) && firstFrame.0.fieldValues==first.fieldValues,"notes_probe_preimage_changed")
 pause(0.04)
 let secondFrame=try observeReadonlyEditor(root,key)
 try require(equalState(secondFrame.1,expected) && secondFrame.0.fieldValues==first.fieldValues,"notes_probe_preimage_changed")
 if foregroundFocus {
  report["notes_probe_stage"]="notes_focus"
  try rawSetNotesProbeFocus(root,expected,key)
 }
 report["notes_probe_stage"]="notes_capabilities"
 do { _=try writableNotesField(root,first) }
 catch {
  // Stable unsupported is a completed readonly diagnosis, not a write.
  try require((error as NSError).localizedDescription=="maintenance_note_text_replacement_unsupported" && report["notes_observation_end"] as? String=="stable_unsupported" && (report["notes_observation_frames"] as? Int ?? 0)>=2,"notes_probe_capabilities_incomplete")
 }
 report["notes_probe_stage"]="notes_structure"
 try notesProbeStructure(root,first.fieldValues)
 let diagnosed=try observeReadonlyEditor(root,key)
 try require(equalState(diagnosed.1,expected) && diagnosed.0.fieldValues==first.fieldValues,"notes_probe_preimage_changed")
 report["notes_probe_stage"]="first_cancel"
 try require(cancel(root,first),"notes_probe_cancel_unverified")
 report["notes_probe_stage"]="preservation_cohort"
 let preserved=try currentNotesProbeCohort(root,expected,original:cohort);bindNotesProbeCohort(preserved)
 report["notes_probe_stage"]="preservation_read"
 let second=try ownedNotesProbeRead(root,target,expected)
 let after=try snapshot(key,second)
 report["notes_probe_stage"]="preservation_state"
 try require(equalState(after,expected),"notes_probe_preservation_changed")
 let finalFrame=try observeReadonlyEditor(root,key)
 try require(equalState(finalFrame.1,expected) && finalFrame.0.fieldValues==second.fieldValues,"notes_probe_preservation_changed")
 report["notes_probe_stage"]="final_cancel"
 let cancelled=cancel(root,second)
 try require(notesProbeOutcomePermits(preimageExact:true,diagnosticsComplete:true,cancelVerified:true,rereadExact:true,finalCancelVerified:cancelled),"notes_probe_final_cancel_unverified")
 report["notes_probe_stage"]="complete"
 var diagnostics:[String:Any]=[:]
 for name in ["notes_role","notes_range_code","notes_text_code","notes_value_code","notes_range_settable","notes_text_settable","notes_value_settable","notes_action_names","notes_actions_code","notes_observation_frames","notes_observation_end","notes_children","notes_internal_focus","notes_probe_stage","notes_probe_row_count","focus_requested","focus_settable","focus_set_code","focus_verified"] {if let value=report[name] {diagnostics[name]=value}}
 return ["ok":true,"probed":true,"synthetic_only":true,"mutation_authorized":false,"current_cohort_only":true,"credentials_changed":0,"journal_modified":false,"app_activated":false,"foreground_focus":foregroundFocus,"diagnostics":diagnostics]
}
func literalNotesStateEqual(_ first:[String:Any],_ second:[String:Any])->Bool {
 guard equalState(first,second),let a=first["notes"] as? String,let b=second["notes"] as? String else{return false}
 return a.utf16.elementsEqual(b.utf16)
}
func syntheticInputFullSelection(_ note:AXUIElement,_ count:Int)->Bool {
 completeDiscovery {()->Bool in
  guard let value=attr(note,kAXSelectedTextRangeAttribute),CFGetTypeID(value)==AXValueGetTypeID() else{return false}
  var range=CFRange()
  return AXValueGetValue(unsafeBitCast(value,to:AXValue.self),.cfRange,&range) && range.location==0 && range.length==count
 }==true
}
// A new positive PID/window/focus/whole-state proof is required immediately
// before AND after each addressed event. Posting itself has no success value.
func syntheticInputEventProof(_ root:AXUIElement,_ key:[String:String],_ expected:[String:Any],_ postimage:[String:Any],_ raw:[String:String],_ note:AXUIElement,allowPostimage:Bool)throws->NativeRead {
 let running=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Passwords")
 try require(running.count==1 && running[0].processIdentifier==appPID && apple(appPID) && front(),"synthetic_input_owner_changed")
 let frame=try observeReadonlyEditor(root,key)
 let original=literalNotesStateEqual(frame.1,expected),planned=literalNotesStateEqual(frame.1,postimage)
 try require(original || (allowPostimage && planned),"synthetic_input_state_changed")
 try require(frame.0.fieldValues.filter{$0.key != "NotesField"}==raw.filter{$0.key != "NotesField"},"synthetic_input_state_changed")
 let proof=completeDiscovery {()->Bool in
  guard let current=notesProbeCurrentNote(frame.0),CFEqual(current,note),
   notesProbeBoundInternalFocus(root,note,editableOnly:true) != nil,
   let window=foregroundNotesProbeWindow,notesProbeAncestorBound(note,window) else{return false}
  return front()
 }
 try require(proof==true,"synthetic_input_focus_changed")
 return frame.0
}
func syntheticForegroundNotesInput(_ expected:[String:Any],_ key:[String:String],_ after:String)throws->[String:Any] {
 report["synthetic_input_stage"]="exact_read"
 ownSyntheticInputAttempted=false
 // The diagnostic current-cohort shortcut is deliberately not used here.
 let (root,n,before)=try readKey(key,leaveOpen:true,guardedExpected:expected)
 ownNotesProbeExpected=expected;ownNotesProbeCleanupAttempted=false
 report["synthetic_input_stage"]="preimage"
 try require(literalNotesStateEqual(before,expected) && syntheticNotesAppendPermits(expected,after),"synthetic_input_preimage_changed")
 let first=try observeReadonlyEditor(root,key);pause(0.04)
 let second=try observeReadonlyEditor(root,key)
 try require(literalNotesStateEqual(first.1,expected) && literalNotesStateEqual(second.1,expected) &&
  first.0.fieldValues==n.fieldValues && second.0.fieldValues==n.fieldValues,"synthetic_input_preimage_changed")
 report["synthetic_input_stage"]="notes_focus"
 try rawSetNotesProbeFocus(root,expected,key)
 guard let note=notesProbeCurrentNote(second.0) else{throw nativeFailure("synthetic_input_note_unverified")}
 var postimage=expected;postimage["notes"]=after
 let old=(expected["notes"] as! String).utf16.count
 report["synthetic_input_stage"]="permission"
 let access=CGPreflightPostEventAccess()
 report["synthetic_input_permission"]=access
 try require(access,"synthetic_input_permission_absent")
 try require(CGEventSource.flagsState(.hidSystemState).rawValue==0,"synthetic_input_physical_modifiers_present")
 var eventCount=0,selectionVerified=false,textAttempted=false
 func send(_ event:CGEvent,phase:String,allowPostimage:Bool,requireSelection:Bool=false)throws {
  _=try syntheticInputEventProof(root,key,expected,postimage,n.fieldValues,note,allowPostimage:allowPostimage)
  let selection = !requireSelection || syntheticInputFullSelection(note,old)
  let windowBound=foregroundNotesProbeWindow.map{notesProbeAncestorBound(note,$0)} ?? false
  let observations:[String:Any]=["requested":true,"synthetic_only":true,"expected":expected,"notes":after,"phase":phase,
   "unique_index":true,"owned_editor":ownEditor != nil,"two_frames":true,"preimage_exact":true,"raw_equal":true,
   "original":Int(foregroundNotesProbeOriginalPID ?? 0),"foreground":Int(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0),
   "passwords":Int(appPID),"keyboard":focusPID().map{Int($0)} as Any,"process_verified":true,"window_bound":windowBound,
   "note_bound":true,"internal_focus_exact":true,"observation_complete":true,"post_access":CGPreflightPostEventAccess(),
   "physical_modifiers_clear":CGEventSource.flagsState(.hidSystemState).rawValue==0,"selection_verified":selectionVerified && selection,
   "input_attempted":false,"deadline_valid":Date()<deadline]
  try require(foregroundNoteInputPermits(observations),"synthetic_input_scope_unverified")
  try require(eventCount<4 && (phase=="selection" ? !textAttempted:true),"synthetic_input_retry_refused")
  // Set attempted provenance before the void post call. There is no global
  // input alternative, per-character retry or clipboard route.
  ownSyntheticInputAttempted=true;eventCount+=1
  report["synthetic_input_event_count"]=eventCount
  event.postToPid(appPID)
  _=try syntheticInputEventProof(root,key,expected,postimage,n.fieldValues,note,allowPostimage:allowPostimage)
 }
 report["synthetic_input_stage"]="selection"
 if !syntheticInputFullSelection(note,old) {
  guard let down=CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:true),let up=CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:false) else{throw nativeFailure("synthetic_input_event_creation_failed")}
  down.flags=[.maskCommand];up.flags=[.maskCommand]
  try send(down,phase:"selection",allowPostimage:false)
  try send(up,phase:"selection",allowPostimage:false)
 }
 let selectionUntil=min(deadline,Date(timeIntervalSinceNow:3));var selectionFrames=0
 while front(),Date()<selectionUntil {
  _=try syntheticInputEventProof(root,key,expected,postimage,n.fieldValues,note,allowPostimage:false)
  if syntheticInputFullSelection(note,old) {selectionFrames+=1;if selectionFrames==2 {selectionVerified=true;break}}
  else {selectionFrames=0}
  pause(0.04)
 }
 report["synthetic_input_selection_verified"]=selectionVerified
 try require(selectionVerified,"synthetic_input_selection_unverified")
 report["synthetic_input_stage"]="text_input"
 guard let down=CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:true),let up=CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:false) else{throw nativeFailure("synthetic_input_event_creation_failed")}
 let units=Array(after.utf16)
 units.withUnsafeBufferPointer {buffer in
  down.keyboardSetUnicodeString(stringLength:buffer.count,unicodeString:buffer.baseAddress!)
  up.keyboardSetUnicodeString(stringLength:buffer.count,unicodeString:buffer.baseAddress!)
 }
 down.flags=[];up.flags=[]
 try send(down,phase:"replacement",allowPostimage:true,requireSelection:true)
 textAttempted=true
 try send(up,phase:"replacement",allowPostimage:true)
 report["synthetic_input_stage"]="postimage"
 let until=min(deadline,Date(timeIntervalSinceNow:3));var observedPost:NativeRead?,postFrames=0
 while front(),Date()<until {
  _=try syntheticInputEventProof(root,key,expected,postimage,n.fieldValues,note,allowPostimage:true)
  let frame=try observeReadonlyEditor(root,key)
  if literalNotesStateEqual(frame.1,postimage) && frame.0.fieldValues.filter({$0.key != "NotesField"})==n.fieldValues.filter({$0.key != "NotesField"}) {
   postFrames+=1;observedPost=frame.0;if postFrames==2 {break}
  } else {postFrames=0;observedPost=nil}
  pause(0.04)
 }
 report["synthetic_input_postimage_verified"]=postFrames==2
 guard postFrames==2,let post=observedPost else{throw nativeFailure("synthetic_input_postimage_unverified")}
 // Register the complete proved postimage. On an error it is still retained
 // for review, never silently canceled or restored after attempted input.
 ownEditor=(root,post);ownEditorFields=post.fieldValues;ownNotesProbeExpected=postimage
 report["synthetic_input_stage"]="save"
 _=try syntheticInputEventProof(root,key,expected,postimage,n.fieldValues,note,allowPostimage:true)
 let savedScope=completeDiscovery {()->AXUIElement? in
  let ns=nodes(root)
  guard fields(ns)==post.fieldValues else{return nil}
  return button(ns,["保存","Save","完成","Done"])
 }
 guard let save=savedScope ?? nil else{throw nativeFailure("synthetic_input_save_unverified")}
 // One semantic AXPress attempt only; no script retry after a lost reply.
 try require(press(save) && waitForList(root),"synthetic_input_save_unverified")
 ownEditor=nil;ownEditorFields=nil;ownNotesProbeExpected=nil;ownNotesProbeCleanupAttempted=false
 report["synthetic_input_stage"]="persisted_read"
 // Discard the filtered row binding before the independent exact query/index
 // read. Preserve a full category cache only if its normal generation guards
 // still validate it; never install the diagnostic cohort as an index.
 indexedLabels=nil;indexedCategory="";indexedQuery="";boundQuery=""
 let (readRoot,reread,state)=try readKey(key,leaveOpen:true,guardedExpected:postimage)
 try require(literalNotesStateEqual(state,postimage),"synthetic_input_persistence_changed")
 let persistedFirst=try observeReadonlyEditor(readRoot,key);pause(0.04)
 let persistedSecond=try observeReadonlyEditor(readRoot,key)
 try require(literalNotesStateEqual(persistedFirst.1,postimage) && literalNotesStateEqual(persistedSecond.1,postimage) &&
  persistedFirst.0.fieldValues==reread.fieldValues && persistedSecond.0.fieldValues==reread.fieldValues,"synthetic_input_persistence_changed")
 report["synthetic_input_persisted_verified"]=true
 report["synthetic_input_stage"]="final_cancel"
 try require(cancel(readRoot,persistedSecond.0),"synthetic_input_final_cancel_unverified")
 report["synthetic_input_stage"]="complete"
 var diagnostics:[String:Any]=[:]
 for name in ["synthetic_input_stage","synthetic_input_event_count","synthetic_input_permission","synthetic_input_selection_verified","synthetic_input_postimage_verified","synthetic_input_persisted_verified","synthetic_input_editor_requires_review","focus_requested","focus_settable","focus_set_code","focus_verified"] {if let value=report[name] {diagnostics[name]=value}}
 return ["ok":true,"synthetic_only":true,"foreground_focus":true,"persisted":true,"credentials_changed":1,
  "app_activated":false,"exports":0,"imports":0,"state":state,"diagnostics":diagnostics]
}
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
 if op=="connect" {
  guard AXIsProcessTrusted(),let original=NSWorkspace.shared.frontmostApplication?.processIdentifier,
   let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.Passwords") else{throw nativeFailure("connect_access_unavailable")}
  var code:SecStaticCode?,requirement:SecRequirement?
  try require(SecStaticCodeCreateWithPath(url as CFURL,[],&code)==errSecSuccess &&
   SecRequirementCreateWithString("identifier \"com.apple.Passwords\" and anchor apple" as CFString,[],&requirement)==errSecSuccess &&
   code != nil && requirement != nil && SecStaticCodeCheckValidity(code!,[],requirement!)==errSecSuccess,"connect_signature_refused")
  let current=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Passwords")
  try require(current.count<=1,"connect_process_ambiguous")
  var needsOpen=current.isEmpty
  if let app=current.first {
   try require(apple(app.processIdentifier),"connect_signature_refused")
   var windows:CFTypeRef?
   try require(AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),kAXWindowsAttribute as CFString,&windows) == .success,"connect_windows_unreadable")
   guard let ws=windows as? [AXUIElement] else{throw nativeFailure("connect_windows_unreadable")}
   needsOpen=ws.isEmpty
  }
  if needsOpen {
   let configuration=NSWorkspace.OpenConfiguration();configuration.activates=false
   var completed=false,failed=false
   NSWorkspace.shared.openApplication(at:url,configuration:configuration) { app,error in failed=error != nil || app==nil;completed=true }
   let until=Date(timeIntervalSinceNow:8)
   while !completed,Date()<until {pause(0.02)}
   try require(completed && !failed,"connect_launch_failed")
  }
  let until=Date(timeIntervalSinceNow:5);var windowCount=0,verified=false
  while Date()<until {
   try require(NSWorkspace.shared.frontmostApplication?.processIdentifier==original,"connect_foreground_changed")
   if let app=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Passwords").first,apple(app.processIdentifier) {
    var windows:CFTypeRef?
    if AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),kAXWindowsAttribute as CFString,&windows) == .success,
     let ws=windows as? [AXUIElement],!ws.isEmpty {windowCount=ws.count;verified=true;break}
   }
   pause(0.05)
  }
  try require(verified,"connect_window_unavailable")
  var value=try execute(["op":"doctor"])
  try require(NSWorkspace.shared.frontmostApplication?.processIdentifier==original,"connect_foreground_changed")
  value.merge(["native_window_count":windowCount,"apple_process_verified":true,"foreground_preserved":true,
   "opened_window":needsOpen,"credentials_changed":0,"imports":0,"exports":0]){_,new in new}
  return value
 }
 if op=="doctor" {
  let running=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Passwords")
  var windowState="access_unavailable",editorCount=0,complete=false
  var searchShape:[String:Any]=["count":0],structure:[String:Int]=[:],fieldRoles:[String:String]=[:],categoryShape:[String:Any]=[:]
  if AXIsProcessTrusted(),running.count==1,apple(running[0].processIdentifier) {
   let ns=nodes(AXUIElementCreateApplication(running[0].processIdentifier))
   for n in ns {structure[text(n,kAXRoleAttribute),default:0]+=1}
   for n in ns where ["TitleField","UserNameField","PasswordField","NotesField"].contains(text(n,kAXIdentifierAttribute)) {fieldRoles[text(n,kAXIdentifierAttribute)]=text(n,kAXRoleAttribute)}
   editorCount=fieldRoles.values.filter{["AXTextField","AXTextArea","AXComboBox"].contains($0)}.count
   let search=ns.filter{text($0,kAXRoleAttribute)=="AXTextField" && text($0,kAXSubroleAttribute)=="AXSearchField"}
   searchShape["count"]=search.count
   if search.count==1 {
    var supported:[String:Bool]=[:]
    for key in [kAXValueAttribute,kAXSelectedTextAttribute,kAXSelectedTextRangeAttribute] {
     var writable=DarwinBoolean(false)
     supported[key]=AXUIElementIsAttributeSettable(search[0],key as CFString,&writable) == .success && writable.boolValue
    }
    var actions:CFArray?
    if AXUIElementCopyActionNames(search[0],&actions) == .success {searchShape["actions"]=actions as? [String] ?? []}
    searchShape["settable"]=supported
    searchShape["children"]=nodes(search[0],prune:false).filter{!CFEqual($0,search[0])}.map{n->[String:Any] in
     var actions:CFArray?
     let names=AXUIElementCopyActionNames(n,&actions) == .success ? (actions as? [String] ?? []):[]
     let known=["取消","Cancel","清除","Clear","清除搜索","Clear Search","取消搜索","Cancel Search","清空搜索"]
     return ["role":text(n,kAXRoleAttribute),"action_names":names,
      "known_cancel_caption":values([n]).contains{known.contains($0)},"identifier_present":!text(n,kAXIdentifierAttribute).isEmpty]
    }
   }
   if editorCount>0 {windowState="user_editor_open"}
   else if ns.contains(where:{text($0,kAXIdentifierAttribute)=="AccountListView"}) && search.count==1 {windowState="unlocked_list_available"}
   else {windowState=unavailableContextStatus(editor:false,incomplete:nativeObservationIncomplete)}
   complete = !nativeObservationIncomplete
   if !complete {windowState="incomplete_window_observation"}
   for category in ["active","deleted"] {
    if let observed=completeDiscovery({categoryEvidence(AXUIElementCreateApplication(running[0].processIdentifier),category)}) {
     var value:[String:Any]=["selected_category_evidence":observed.0,"published_count_known":observed.1 != nil]
     if let count=observed.1 {value["published_count"]=count}
     categoryShape[category]=value
    }
   }
  }
  return ["ok":true,"backend":"apple-passwords-accessibility","capabilities":["read","notes-set","delete-redundant-note"],
   "apple_live_verified":false,"accessibility_trusted":AXIsProcessTrusted(),"apple_running":running.count==1,"window_state":windowState,
   "window_observation_complete":complete,"editor_field_count":editorCount,"search_field":searchShape,
   "role_counts":structure,"field_roles":fieldRoles,"category_observation":categoryShape,
   "passwords_frontmost":running.count==1 && NSWorkspace.shared.frontmostApplication?.processIdentifier==running[0].processIdentifier,
   "whole_vault_public_api":false,"native_protocol_delete_assumed":false]
 }
 try require(["read","deleted-read","notes-set","delete-redundant-note","recover-readonly-editor","notes-editor-probe","synthetic-foreground-notes-input"].contains(op),"operation_unsupported")
 let recovery=q["expected"] as? [String:Any]
 var foregroundFocus=false
 guard let key=(q["key"] as? [String:String]) ?? (["recover-readonly-editor","notes-editor-probe"].contains(op) ? recovery?["key"] as? [String:String]:nil),Set(key.keys)==Set(["title","username"]),!(key["title"] ?? "").isEmpty else{throw nativeFailure("identity_invalid")}
 if op=="notes-editor-probe" {
  report["notes_probe_stage"]="input_validation"
  guard let requested=notesProbeForegroundFocusOption(q["foreground_focus"]) else{throw nativeFailure("notes_probe_focus_option_invalid")}
  foregroundFocus=requested
  report["focus_requested"]=requested;report["focus_settable"]=false;report["focus_verified"]=false
  try require(q["synthetic_only"] as? Bool==true && recovery != nil && notesProbeFixtureValid(recovery!) && (recovery!["key"] as? [String:String])==key,"notes_probe_synthetic_input_required")
 }
 if op=="synthetic-foreground-notes-input" {
  report["synthetic_input_stage"]="input_validation"
  report["synthetic_input_event_count"]=0;report["synthetic_input_permission"]=false
  report["synthetic_input_selection_verified"]=false;report["synthetic_input_postimage_verified"]=false
  report["synthetic_input_persisted_verified"]=false;report["synthetic_input_editor_requires_review"]=false
  try require(q["synthetic_only"] != nil && q["foreground_focus"] != nil &&
   notesProbeForegroundFocusOption(q["synthetic_only"])==true && notesProbeForegroundFocusOption(q["foreground_focus"])==true,
   "synthetic_input_explicit_flags_required")
  guard let expected=recovery,let after=q["notes"] as? String,(expected["key"] as? [String:String])==key,
   syntheticNotesAppendPermits(expected,after) else{throw nativeFailure("synthetic_input_fixture_required")}
  foregroundFocus=true
  report["focus_requested"]=true;report["focus_settable"]=false;report["focus_verified"]=false
 }
 if appPID==0,!["notes-editor-probe","synthetic-foreground-notes-input"].contains(op) {
  if NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Passwords").isEmpty {_=try execute(["op":"connect"])}
 }
 let applications=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Passwords")
 guard applications.count==1,let a=applications.first,apple(a.processIdentifier) else{throw nativeFailure("native_access_unavailable")}
 if appPID != a.processIdentifier {
  activeLabels=nil;deletedLabels=nil;indexedLabels=nil;currentCategory="";indexedCategory="";indexedQuery="";boundQuery="";failedIndexCategories=[];valueSearchAvailable=true
 }
 appPID=a.processIdentifier
 if ["notes-editor-probe","synthetic-foreground-notes-input"].contains(op),foregroundFocus {
  if op=="synthetic-foreground-notes-input" {report["synthetic_input_stage"]="foreground_owner"}
  try beginForegroundNotesProbeLease()
 }
 try acquireRequestLease()
 var windows:CFTypeRef?
 let windowsCode=AXUIElementCopyAttributeValue(AXUIElementCreateApplication(appPID),kAXWindowsAttribute as CFString,&windows)
 if op=="notes-editor-probe" {
  try require(windowsCode == .success && (windows as? [AXUIElement])?.isEmpty==false,"notes_probe_window_unavailable")
  return try notesEditorProbe(recovery!,key,foregroundFocus:foregroundFocus)
 }
 if op=="synthetic-foreground-notes-input" {
  try require(windowsCode == .success && (windows as? [AXUIElement])?.isEmpty==false,"synthetic_input_window_unavailable")
  return try syntheticForegroundNotesInput(recovery!,key,q["notes"] as! String)
 }
 if windowsCode == .success,let ws=windows as? [AXUIElement],ws.isEmpty {_=try execute(["op":"connect"])}
 if op=="recover-readonly-editor" {
  guard let expected=recovery else{throw nativeFailure("editor_recovery_snapshot_invalid")}
  return try recoverReadonlyEditor(expected)
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
  // AXValue changed the visible editor without changing SwiftUI's saved model
  // in the live synthetic test. Complete SelectedText replacement is the only
  // supported write path; no field focus or injected input is used.
  let note=try writableNotesField(root,n),old=before["notes"] as? String ?? "",ownerBefore=NSWorkspace.shared.frontmostApplication?.processIdentifier,keyboardBefore=focusPID()
  var full=CFRange(location:0,length:old.utf16.count)
  guard let selection=AXValueCreate(.cfRange,&full),set(note,kAXSelectedTextRangeAttribute,selection),let seen=attr(note,kAXSelectedTextRangeAttribute),CFGetTypeID(seen)==AXValueGetTypeID() else{throw nativeFailure("note_selection_unverified")}
  var actual=CFRange();try require(AXValueGetValue(unsafeBitCast(seen,to:AXValue.self),.cfRange,&actual) && actual.location==0 && actual.length==full.length,"note_selection_unverified")
  try require(set(note,kAXSelectedTextAttribute,after as CFString),"note_text_replacement_refused")
  try require(NSWorkspace.shared.frontmostApplication?.processIdentifier==ownerBefore && focusPID()==keyboardBefore && front(),"note_owner_changed")
  let current=fields(nodes(root));var wanted=n.fieldValues;wanted["NotesField"]=after
  if current.filter({$0.key != "NotesField"})==n.fieldValues.filter({$0.key != "NotesField"}),current["NotesField"] != nil {ownEditorFields=current}
  guard current==wanted,!nativeObservationIncomplete,let save=button(nodes(root),["保存","Save","完成","Done"]),boundedClick(save,root) else{throw nativeFailure("note_save_unverified")}
  try require(waitForList(root),"note_save_unverified")
  ownEditor=nil;ownEditorFields=nil;ownNotesProbeExpected=nil;ownNotesProbeCleanupAttempted=false
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
 let permanent=button(ns,["永久删除","立即永久删除","Delete Permanently","Permanently Delete"]) != nil
 let confirm=button(ns,["删除密码","删除备注","删除此密码","删除","Delete Password","Delete Note","Delete"])
 try require(recoverableDialog(words:words,ordinaryButton:confirm != nil,permanentButton:permanent) && fields(nodes(root))==n.fieldValues && !nativeObservationIncomplete,"recoverable_confirmation_refused")
 let note=before["notes"] as? String ?? ""
 let syntheticItem=Item(id:"native-maintenance",title:before["native_title"] as? String ?? "",expected_note:note,source_ids:[],retained:Target(title:"",native_title:"",username:"",notes:"",urls:[]))
 try require(confirmRecoverable(syntheticItem),"delete_outcome_requires_review")
 ownEditor=nil;ownEditorFields=nil;ownNotesProbeExpected=nil;ownNotesProbeCleanupAttempted=false
 try require(waitForList(root),"delete_outcome_requires_review")
 // Update a complete unfiltered index only after the current row count proves
 // the expected single removal. A filtered snapshot is never reused as All.
 guard let (_,list)=context(root),let rows=attr(list,kAXRowsAttribute) as? [AXUIElement],var filterLabels=indexedLabels,
  sameIndexScope(cachedCategory:indexedCategory,cachedQuery:indexedQuery,category:"active",query:boundQuery) else{throw nativeFailure("delete_outcome_requires_review")}
 let filteredMatches=filterLabels.indices.filter{filterLabels[$0].contains(key["title"]!)}
 try require(filteredMatches.count==1 && rows.count==filterLabels.count-1,"delete_outcome_requires_review")
 filterLabels.remove(at:filteredMatches[0]);indexedLabels=filterLabels
 if var fullLabels=activeLabels {
  let fullMatches=fullLabels.indices.filter{fullLabels[$0].contains(key["title"]!)}
  try require(fullMatches.count==1,"delete_outcome_requires_review")
  fullLabels.remove(at:fullMatches[0]);activeLabels=fullLabels
 }
 deletedLabels=nil
 return ["ok":true,"recoverable":true]
}

// A single process owns one list index for the complete bounded CLI batch.
guard args==["--serve"] else {fputs("maintenance_invalid_entry_point\n",stderr);exit(2)}
while let line=readLine(strippingNewline:true) {
 deadline=Date(timeIntervalSinceNow:90);nativeObservationIncomplete=false
 foregroundNotesProbeWindow=nil;foregroundNotesProbeOriginalPID=nil
 for key in ["confirmation_bridge_failure","confirmation_native_editor_role","confirmation_bridge_timed_out","confirmation_account_list_enumerated","confirmation_bridge_exit_code","confirmation_bridge_system_error_code","confirmation_editor_path_depth","failure_stage","status","ui_set_attribute","ui_set_error_code","ui_press_error_code","request_owner_mode","search_strategy","search_witness_failure","native_incomplete_error_counts","owner_guard_observation","search_phase","search_wait_end","search_result_count","search_clear_method","search_clear_failure","search_clear_before_count","search_clear_after_count","bounded_click_bridge_exit_code","bounded_click_bridge_failure","bounded_click_bridge_error_code","notes_role","notes_range_code","notes_text_code","notes_value_code","notes_range_settable","notes_text_settable","notes_value_settable","notes_action_names","notes_actions_code","notes_observation_frames","notes_observation_end","notes_children","notes_internal_focus","notes_probe_stage","notes_probe_row_count","notes_probe_read_opened","notes_probe_recovery_attempted","notes_probe_editor_recovered","notes_probe_editor_requires_review","focus_requested","focus_settable","focus_set_code","focus_verified","synthetic_input_stage","synthetic_input_event_count","synthetic_input_permission","synthetic_input_selection_verified","synthetic_input_postimage_verified","synthetic_input_persisted_verified","synthetic_input_editor_requires_review"] {report[key]=nil}
 var response:[String:Any]=["ok":false,"app_activated":false,"backend":"apple-passwords-accessibility"]
 do {
  guard line.utf8.count<=4*1024*1024,let bytes=line.data(using:.utf8),let q=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],let id=q["id"] as? Int else{throw nativeFailure("request_invalid")}
  response["id"]=id
  response.merge(try execute(q)){_,new in new}
 } catch {
  closeOwnEditor()
  let message=(error as NSError).localizedDescription
  response["error"]=message.hasPrefix("maintenance_") && message.dropFirst(12).allSatisfy({$0.isLowercase || $0=="_"}) ? message:"maintenance_native_operation_failed"
  // Return only structural reasons. Never expose field values in diagnostics.
  var diagnostics:[String:Any]=[:]
  for key in ["confirmation_bridge_failure","confirmation_native_editor_role","confirmation_bridge_timed_out","confirmation_account_list_enumerated","confirmation_bridge_exit_code","confirmation_bridge_system_error_code","confirmation_editor_path_depth","failure_stage","status","ui_set_attribute","ui_set_error_code","ui_press_error_code","request_owner_mode","search_strategy","search_witness_failure","native_incomplete_error_counts","owner_guard_observation","all_list_bridge_failure","all_list_bridge_stage","all_list_bridge_error_code","all_list_bridge_exit_code","all_list_bridge_timed_out","search_clear_method","search_clear_failure","search_clear_before_count","search_clear_after_count","bounded_click_bridge_exit_code","bounded_click_bridge_failure","bounded_click_bridge_error_code","search_phase","search_wait_end","search_result_count","notes_role","notes_range_code","notes_text_code","notes_value_code","notes_range_settable","notes_text_settable","notes_value_settable","notes_action_names","notes_actions_code","notes_observation_frames","notes_observation_end","notes_children","notes_internal_focus","notes_probe_stage","notes_probe_row_count","notes_probe_read_opened","notes_probe_recovery_attempted","notes_probe_editor_recovered","notes_probe_editor_requires_review","focus_requested","focus_settable","focus_set_code","focus_verified","synthetic_input_stage","synthetic_input_event_count","synthetic_input_permission","synthetic_input_selection_verified","synthetic_input_postimage_verified","synthetic_input_persisted_verified","synthetic_input_editor_requires_review"] {
   if let value=report[key] {diagnostics[key]=value}
  }
  response["diagnostics"]=diagnostics
 }
 foregroundNotesProbeWindow=nil;foregroundNotesProbeOriginalPID=nil
 if let bytes=try? JSONSerialization.data(withJSONObject:response,options:[.sortedKeys]),let text=String(data:bytes,encoding:.utf8) {print(text);fflush(stdout)}
}
closeOwnEditor()
