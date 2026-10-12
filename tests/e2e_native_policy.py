#!/usr/bin/env python3
"""Native helper pure request-lease/query policy through the real executable."""
import argparse,json,pathlib,shlex,subprocess
p=argparse.ArgumentParser();p.add_argument('--helper',required=True);p.add_argument('--report',required=True);a=p.parse_args()
cases=[
 ('rebind foreground session to a new background request',{'operation':'lease','foreground':91,'passwords':92,'keyboard':91,'owned_editor':False},'background'),
 ('foreground request uses current explicit owner',{'operation':'lease','foreground':92,'passwords':92,'keyboard':92,'owned_editor':False},'foreground'),
 ('unknown foreground is refused',{'operation':'lease','foreground':0,'passwords':92,'keyboard':None,'owned_editor':False},'refuse'),
 ('background request with Passwords keyboard focus is refused',{'operation':'lease','foreground':91,'passwords':92,'keyboard':92,'owned_editor':False},'refuse'),
 ('foreground request with another keyboard owner is refused',{'operation':'lease','foreground':92,'passwords':92,'keyboard':91,'owned_editor':False},'refuse'),
 ('owned editor cannot renew lease',{'operation':'lease','foreground':91,'passwords':92,'keyboard':91,'owned_editor':True},'preserve'),
 ('absent keyboard owner permits addressed background request',{'operation':'lease','foreground':91,'passwords':92,'keyboard':None,'owned_editor':False},'background'),
 ('unsupported text replacement uses complete index',{'operation':'query','range_settable':False,'text_settable':False},'unfiltered-index'),
 ('partial text replacement uses complete index',{'operation':'query','range_settable':True,'text_settable':False},'unfiltered-index'),
 ('both text selection attributes permit bounded search',{'operation':'query','range_settable':True,'text_settable':True},'selected-text'),
 ('value setter requires a witnessed search model',{'operation':'query','range_settable':False,'text_settable':False,'value_settable':True},'witnessed-value'),
 ('witness requires an actual empty sentinel list',{'operation':'witness','empty_seen':False,'stable_complete':True,'owner_unchanged':True,'count':1},False),
 ('witness refuses incomplete target observation',{'operation':'witness','empty_seen':True,'stable_complete':False,'owner_unchanged':True,'count':1},False),
 ('witness refuses owner change',{'operation':'witness','empty_seen':True,'stable_complete':True,'owner_unchanged':False,'count':1},False),
 ('witness refuses an unbounded target list',{'operation':'witness','empty_seen':True,'stable_complete':True,'owner_unchanged':True,'count':101},False),
 ('witness accepts stable complete bounded results after empty sentinel',{'operation':'witness','empty_seen':True,'stable_complete':True,'owner_unchanged':True,'count':1},True),
 ('empty target still requires a complete unfiltered absence proof',{'operation':'witness','empty_seen':True,'stable_complete':True,'owner_unchanged':True,'count':0},False),
 ('bare 30 is not proof of recoverability',{'operation':'recoverable-dialog','words':['delete item 30'],'ordinary_button':True,'permanent_button':False},False),
 ('named recently deleted location proves recoverability',{'operation':'recoverable-dialog','words':['Items will move to Recently Deleted'],'ordinary_button':True,'permanent_button':False},True),
 ('Chinese recovery wording proves recoverability',{'operation':'recoverable-dialog','words':['此密码可以在30天内恢复'],'ordinary_button':True,'permanent_button':False},True),
 ('permanent delete button always refuses',{'operation':'recoverable-dialog','words':['Recently Deleted'],'ordinary_button':True,'permanent_button':True},False),
 ('no exact ordinary button refuses',{'operation':'recoverable-dialog','words':['Recently Deleted'],'ordinary_button':False,'permanent_button':False},False),
 ('Password NotesField can be a text field',{'operation':'selection-scope','role':'AXTextField','identifier':'NotesField','subrole':''},True),
 ('multiline NotesField remains supported',{'operation':'selection-scope','role':'AXTextArea','identifier':'NotesField','subrole':''},True),
 ('password field cannot receive selected-text writes',{'operation':'selection-scope','role':'AXTextField','identifier':'PasswordField','subrole':''},False),
 ('ordinary username cannot receive selected-text writes',{'operation':'selection-scope','role':'AXTextField','identifier':'UserNameField','subrole':''},False),
 ('owned search field can receive selected-text writes',{'operation':'selection-scope','role':'AXTextField','identifier':'','subrole':'AXSearchField'},True),
 ('bounded selected-text query never requires initial clearing',{'operation':'query-clear-policy','full_index':False,'query_empty':False},False),
 ('full-index request clears a nonempty query',{'operation':'query-clear-policy','full_index':True,'query_empty':False},True),
 ('already empty full-index query needs no clear action',{'operation':'query-clear-policy','full_index':True,'query_empty':True},False),
 ('Chinese All header identifies active category',{'operation':'category-caption','category':'active','value':'正在搜索“全部”'},True),
 ('English All header identifies active category',{'operation':'category-caption','category':'active','value':'Searching “All”'},True),
 ('Deleted header cannot identify active category',{'operation':'category-caption','category':'active','value':'Recently Deleted'},False),
 ('All header cannot identify deleted category',{'operation':'category-caption','category':'deleted','value':'All'},False),
 ('arbitrary All mention is not category proof',{'operation':'category-caption','category':'active','value':'my All account'},False),
 ('exact Deleted header identifies deleted category',{'operation':'category-caption','category':'deleted','value':'已删除'},True),
 ('editable verification seed text field prevents recovery',{'operation':'editor-code-guard','roles':['AXTextField']},False),
 ('editable verification seed text area prevents recovery',{'operation':'editor-code-guard','roles':['AXTextArea']},False),
 ('editable verification seed combo prevents recovery',{'operation':'editor-code-guard','roles':['AXComboBox']},False),
 ('static generated code is not confused with an editable seed',{'operation':'editor-code-guard','roles':['AXStaticText']},True),
 ('one editable verification field among static labels prevents recovery',{'operation':'editor-code-guard','roles':['AXStaticText','AXTextField']},False),
 ('two complete writable note observations allow one SelectedText attempt',{'operation':'notes-write-policy','role':'AXTextField','range_code':0,'text_code':0,'value_code':0,'range_settable':True,'text_settable':True,'two_frames':True,'fields_equal':True},True),
 ('one note observation cannot authorize a write',{'operation':'notes-write-policy','role':'AXTextField','range_code':0,'text_code':0,'value_code':0,'range_settable':True,'text_settable':True,'two_frames':False,'fields_equal':True},False),
 ('transient range error is not writable',{'operation':'notes-write-policy','role':'AXTextField','range_code':-25204,'text_code':0,'value_code':0,'range_settable':True,'text_settable':True,'two_frames':True,'fields_equal':True},False),
 ('stale text element is not writable',{'operation':'notes-write-policy','role':'AXTextField','range_code':0,'text_code':-25201,'value_code':0,'range_settable':True,'text_settable':True,'two_frames':True,'fields_equal':True},False),
 ('unsupported selected-text field never falls back to value writes',{'operation':'notes-write-policy','role':'AXTextField','range_code':0,'text_code':-25205,'value_code':0,'range_settable':True,'text_settable':False,'two_frames':True,'fields_equal':True},False),
 ('changed editable fields refuse the note write',{'operation':'notes-write-policy','role':'AXTextField','range_code':0,'text_code':0,'value_code':0,'range_settable':True,'text_settable':True,'two_frames':True,'fields_equal':False},False),
 ('static note role cannot authorize selected-text writes',{'operation':'notes-write-policy','role':'AXStaticText','range_code':0,'text_code':0,'value_code':0,'range_settable':True,'text_settable':True,'two_frames':True,'fields_equal':True},False),
 ('multiline note requires the same complete observations',{'operation':'notes-write-policy','role':'AXTextArea','range_code':0,'text_code':0,'value_code':0,'range_settable':True,'text_settable':True,'two_frames':True,'fields_equal':True},True),
 ('unsupported optional value attribute does not authorize a value write',{'operation':'notes-write-policy','role':'AXTextField','range_code':0,'text_code':0,'value_code':-25205,'range_settable':True,'text_settable':True,'two_frames':True,'fields_equal':True},True),
 ('transient optional value observation still holds',{'operation':'notes-write-policy','role':'AXTextField','range_code':0,'text_code':0,'value_code':-25204,'range_settable':True,'text_settable':True,'two_frames':True,'fields_equal':True},False),
 ('cached filtered index cannot satisfy unfiltered request',{'operation':'cache','cached_category':'active','cached_query':'synthetic','category':'active','query':''},False),
 ('cached other category cannot satisfy active request',{'operation':'cache','cached_category':'deleted','cached_query':'','category':'active','query':''},False),
 ('complete active index can be reused only in its scope',{'operation':'cache','cached_category':'active','cached_query':'','category':'active','query':''},True),
]
sample={'key':{'title':'synthetic','username':'synthetic@example.invalid'},'native_title':'synthetic','notes':'synthetic preserved notes','password':'synthetic password','sites':['https://synthetic.invalid'],'sharing':'unshared','otp':'absent','passkey':'unknown','extra_fields':[]}
probe_expected={'key':{'title':'apw API 测试 · SSO 与备注','username':'synthetic-google@example.invalid'},'native_title':'apw API 测试 · SSO 与备注','notes':'APW_EXCHANGE_SYNTHETIC_V1 preserved notes','password':'','sites':['https://apw-exchange-demo.invalid'],'sharing':'unshared','otp':'absent','passkey':'unknown','extra_fields':[]}
probe_input={'operation':'notes-probe-boundary','expected':probe_expected,'synthetic_only':True,'count':3,'complete':True,'stable':True,'unique':True,'no_editor':True,'owner_bound':True}
for name, changes, expected_result in [
 ('existing synthetic stable cohort can be diagnosed',{},True),
 ('probe cannot omit synthetic boundary',{'synthetic_only':False},False),
 ('probe refuses an empty cohort',{'count':0},False),
 ('probe refuses an unbounded cohort',{'count':101},False),
 ('probe refuses an incomplete cohort',{'complete':False},False),
 ('probe refuses an unstable cohort',{'stable':False},False),
 ('probe refuses a duplicate within the cohort',{'unique':False},False),
 ('probe cannot close an existing user editor',{'no_editor':False},False),
 ('probe refuses a changed owner',{'owner_bound':False},False),
 ('probe refuses a missing full preimage',{'expected':{'key':probe_expected['key']}},False),
 ('probe refuses an ordinary account title',{'expected':{**probe_expected,'key':{**probe_expected['key'],'title':'Customer Account'}}},False),
 ('probe requires the original synthetic note marker',{'expected':{**probe_expected,'notes':'ordinary notes'}},False),
 ('probe refuses a real account username',{'expected':{**probe_expected,'key':{**probe_expected['key'],'username':'person@example.com'}}},False),
 ('probe refuses a real website',{'expected':{**probe_expected,'sites':['https://example.com']}},False),
 ('probe refuses a nonempty credential',{'expected':{**probe_expected,'password':'unknown password'}},False),
 ('probe refuses unexpected extra editable data',{'expected':{**probe_expected,'extra_fields':[{'role':'AXTextField','id':'unexpected','value':'unknown'}]}},False),
]: cases.append((name,{**probe_input,**changes},expected_result))
probe_outcome={'operation':'notes-probe-outcome','preimage_exact':True,'diagnostics_complete':True,'cancel_verified':True,'reread_exact':True,'final_cancel_verified':True}
for name,changes,expected_result in [
 ('only complete two-cancel preservation proves probe success',{},True),
 ('wrong original record cannot report probe success',{'preimage_exact':False},False),
 ('incomplete diagnostics cannot report probe success',{'diagnostics_complete':False},False),
 ('first cancellation failure cannot report probe success',{'cancel_verified':False},False),
 ('wrong reopened original state cannot report probe success',{'reread_exact':False},False),
 ('final cancellation failure cannot report probe success',{'final_cancel_verified':False},False),
]: cases.append((name,{**probe_outcome,**changes},expected_result))
probe_focus={'operation':'notes-probe-focus','copy_code':0,'pid_code':0,'role_code':0,'same_pid':True,'ancestor_bound':True,'role':'AXTextArea'}
for name,changes,expected_result in [
 ('only an owned bound editable internal focus matches the note',{},True),
 ('unavailable internal focus grants no match',{'copy_code':-25212},False),
 ('foreign internal focus grants no match',{'same_pid':False},False),
 ('stale internal focus grants no match',{'pid_code':-25201},False),
 ('unreadable focus role grants no match',{'role_code':-25204},False),
 ('a different application field grants no note match',{'ancestor_bound':False},False),
 ('an internal button is not an editable note endpoint',{'role':'AXButton'},False),
]: cases.append((name,{**probe_focus,**changes},expected_result))
probe_cleanup={'operation':'notes-probe-read-cleanup','returned_complete':False,'opened_by_read':True,'owner_unchanged':True,'expected_complete':True,'list_available':False}
for name,changes,expected_result in [
 ('proven readonly opening may attempt one exact expected recovery',{},'recover_expected_once'),
 ('complete NativeRead is owned before snapshot construction',{'returned_complete':True},'register_before_snapshot'),
 ('unobserved opening cannot cancel a user editor',{'opened_by_read':False},'requires_review'),
 ('changed owner cannot trigger expected recovery',{'owner_unchanged':False},'requires_review'),
 ('partial expected state cannot trigger recovery',{'expected_complete':False},'requires_review'),
 ('complete returned read without a proven owned opening still holds',{'returned_complete':True,'opened_by_read':False},'requires_review'),
 ('read failure with a verified list has no editor to cancel',{'opened_by_read':False,'list_available':True},'no_owned_editor'),
]: cases.append((name,{**probe_cleanup,**changes},expected_result))
focus_owner={'operation':'notes-probe-foreground-owner','original':92,'foreground':92,'passwords':92,'keyboard':92,'deadline_valid':True,'internal_complete':True,'internal_bound':True}
for name,changes,expected_result in [
 ('explicit foreground diagnostic keeps its original Passwords owner',{},True),
 ('nil global keyboard focus requires positive internal application evidence',{'keyboard':None},True),
 ('known foreign keyboard owner refuses foreground focus',{'keyboard':91},False),
 ('another original foreground owner cannot be promoted',{'original':91},False),
 ('a frontmost owner change stops the diagnostic',{'foreground':91},False),
 ('unknown Passwords PID refuses the diagnostic',{'passwords':0},False),
 ('expired focus diagnostic lease refuses',{'deadline_valid':False},False),
 ('nil global keyboard without complete internal proof refuses',{'keyboard':None,'internal_complete':False},False),
 ('internal focus in an unbound window refuses',{'internal_bound':False},False),
]:cases.append((name,{**focus_owner,**changes},expected_result))
focus_setter={'operation':'notes-probe-focus-setter','requested':True,'expected':probe_expected,'owned_editor':True,'two_frames':True,'state_exact':True,'unique_note':True,'same_pid':True,'complete_scope':True,'identifier':'NotesField','role':'AXTextField','owner_valid':True,'settable_code':0,'settable':True}
for name,changes,expected_result in [
 ('only explicit owned full synthetic scope permits one focus attempt',{},True),
 ('default diagnostic never authorizes a focus setter',{'requested':False},False),
 ('foreground focus cannot target an ordinary account',{'expected':sample},False),
 ('foreground focus cannot claim an unowned editor',{'owned_editor':False},False),
 ('one preimage frame cannot authorize focus',{'two_frames':False},False),
 ('changed canonical state refuses even a focus setter',{'state_exact':False},False),
 ('ambiguous note target refuses focus',{'unique_note':False},False),
 ('incomplete identifier or PID discovery cannot authorize note focus',{'complete_scope':False},False),
 ('foreign NotesField refuses focus',{'same_pid':False},False),
 ('another editable field cannot receive note focus',{'identifier':'PasswordField'},False),
 ('a static note cannot receive editing focus',{'role':'AXStaticText'},False),
 ('changed owner cannot authorize focus',{'owner_valid':False},False),
 ('unsupported focus setter holds without a fallback',{'settable':False},False),
 ('transient settable query does not authorize focus',{'settable_code':-25204},False),
 ('multiline exact synthetic note may receive editing focus',{'role':'AXTextArea'},True),
]:cases.append((name,{**focus_setter,**changes},expected_result))
for name, option, expected_result in [
 ('omitted foreground-focus defaults to false',{},'false'),
 ('explicit false does not request focus',{'value':False},'false'),
 ('explicit true requests foreground scope',{'value':True},'true'),
 ('numeric one is not explicit focus authorization',{'value':1},'invalid'),
 ('numeric zero is not a JSON Boolean',{'value':0},'invalid'),
 ('string true is not explicit focus authorization',{'value':'true'},'invalid'),
 ('null foreground focus option refuses',{'value':None},'invalid'),
]:cases.append((name,{'operation':'notes-probe-focus-option',**option},expected_result))
cleanup_state={'operation':'notes-probe-error-cleanup','expected':probe_expected,'first':probe_expected,'second':probe_expected,'complete':True,'owned_editor':True,'owner_valid':True,'raw_equal':True}
for name,changes,expected_result in [
 ('only two full exact owned probe states permit error cleanup',{},True),
 ('changed website label refuses cleanup despite equal empty WebsiteField',{'second':{**probe_expected,'sites':[]}},False),
 ('changed first website frame cannot be hidden by a restored second frame',{'first':{**probe_expected,'sites':[]}},False),
 ('changed sharing refuses cleanup despite equal raw fields',{'second':{**probe_expected,'sharing':'unknown'}},False),
 ('changed OTP association refuses cleanup despite equal raw fields',{'second':{**probe_expected,'otp':'unknown'}},False),
 ('changed passkey association refuses cleanup despite equal raw fields',{'second':{**probe_expected,'passkey':'absent'}},False),
 ('staged raw field change refuses cleanup',{'raw_equal':False},False),
 ('incomplete canonical observation refuses probe error cleanup',{'complete':False},False),
 ('unowned editor cannot receive probe error cleanup',{'owned_editor':False},False),
 ('changed owner refuses probe error cleanup',{'owner_valid':False},False),
]:cases.append((name,{**cleanup_state,**changes},expected_result))
for name, observed, complete, unique, expected_result in [
 ('whole unchanged editor may be recovered',sample,True,True,True),
 ('incomplete editor may not be recovered',sample,False,True,False),
 ('ambiguous editor may not be recovered',sample,True,False,False),
 ('changed password may not be discarded',{**sample,'password':'changed synthetic password'},True,True,False),
 ('changed notes may not be discarded',{**sample,'notes':'new synthetic notes'},True,True,False),
 ('changed websites may not be discarded',{**sample,'sites':[]},True,True,False),
 ('missing fields may not be discarded',{'key':sample['key'],'notes':sample['notes']},True,True,False),
]:
 cases.append((name,{'operation':'editor-recovery','expected':sample,'observed':observed,'complete':complete,'unique':unique},expected_result))
checks=[];failure=None
try:
 for name,observation,expected in cases:
  result=subprocess.run([a.helper,'--policy-test'],input=json.dumps(observation)+'\n',capture_output=True,text=True,timeout=5)
  value=json.loads(result.stdout)
  ok=result.returncode==0 and value.get('result')==expected and value.get('apple_accessed') is False
  checks.append({'name':name,'passed':ok});assert ok,name
except Exception as e:failure=type(e).__name__+': '+str(e)
report={'passed':failure is None,'checks':checks,'error':failure,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--helper',a.helper,'--report',a.report]),'boundary':'real native executable isolated lease/query policies; no NSApplication or Apple record access','real_apple_mutations_verified':False}
pathlib.Path(a.report).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks),'error':failure}));raise SystemExit(0 if report['passed'] else 1)
