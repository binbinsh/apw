#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Replay bounded query-only clear recovery decisions before AppKit starts."""
import argparse, hashlib, json, pathlib, shlex, subprocess

p = argparse.ArgumentParser()
p.add_argument('--helper', required=True)
p.add_argument('--report', required=True)
a = p.parse_args()
base = {'operation': 'search-clear-recovery', 'phase': 'prepare',
        'complete': True, 'owner_unchanged': True, 'category_matches': True,
        'unique_search': True, 'window_bound': True, 'sentinel_matches': False,
        'range_code': 0, 'text_code': 0, 'value_code': 0,
        'range_settable': False, 'text_settable': False, 'value_settable': True,
        'semantic_clear': 'absent', 'captions': []}
cases = [
    ('semantic clear needs no sentinel', {'semantic_clear': 'usable', 'value_settable': False}, 'press-clear'),
    ('caption alone cannot substitute for semantic clear', {'captions': [['Cancel']]}, 'set-sentinel'),
    ('search icon is not clear', {'captions': [['', '搜索']]}, 'set-sentinel'),
    ('empty caption is not clear', {'captions': [['']]}, 'set-sentinel'),
    ('no clear seeds once', {}, 'set-sentinel'),
    ('selected text keeps preferred route', {'range_settable': True, 'text_settable': True}, 'selected-text'),
    ('partial selected text capability still allows value route', {'range_settable': True}, 'set-sentinel'),
    ('unknown semantic attribute refuses', {'semantic_clear': 'unknown'}, 'hold'),
    ('unbound disabled foreign or actionless clear refuses', {'semantic_clear': 'invalid'}, 'hold'),
    ('captions alone never authorize a button press', {'captions': [['Cancel'], ['Clear']]}, 'set-sentinel'),
    ('false value capability refuses seed', {'value_settable': False}, 'hold'),
    ('value capability error refuses seed', {'value_code': -25204}, 'hold'),
    ('range query error refuses', {'range_code': -25204}, 'hold'),
    ('text query error refuses', {'text_code': -25202}, 'hold'),
    ('invalid phase refuses', {'phase': 'retry'}, 'hold'),
    ('after sentinel semantic clear preferred', {'phase': 'sentinel_observed', 'sentinel_matches': True, 'semantic_clear': 'usable'}, 'press-clear'),
    ('after sentinel caption cannot replace semantic binding', {'phase': 'sentinel_observed', 'sentinel_matches': True, 'captions': [['清除搜索']]}, 'set-empty'),
    ('after sentinel no clear permits one empty setter', {'phase': 'sentinel_observed', 'sentinel_matches': True, 'captions': [['搜索']]}, 'set-empty'),
    ('after sentinel stale visible value refuses', {'phase': 'sentinel_observed'}, 'hold'),
    ('after sentinel clear observation unknown refuses fallback', {'phase': 'sentinel_observed', 'sentinel_matches': True, 'semantic_clear': 'unknown'}, 'hold'),
    ('semantic noValue is explicit absence regardless of unrelated captions', {'phase': 'sentinel_observed', 'sentinel_matches': True, 'captions': [['Clear'], ['Clear']]}, 'set-empty'),
]
for flag in ['complete', 'owner_unchanged', 'category_matches', 'unique_search', 'window_bound']:
    cases.append((flag + ' missing refuses any action', {flag: False, 'semantic_clear': 'usable'}, 'hold'))
binding = {'operation': 'search-clear-binding', 'clear_code': 0, 'element_type': True,
           'pid_code': 0, 'parent_code': 0, 'role_code': 0, 'enabled_code': 0, 'actions_code': 0,
           'same_pid': True, 'parent_is_search': True, 'role': 'AXButton', 'enabled': True, 'press_action': True}
bindings = [('bound enabled semantic Clear is usable', {}, 'usable'),
            ('only explicit noValue means no Clear', {'clear_code': -25212}, 'absent'),
            ('unsupported is not semantic absence', {'clear_code': -25205}, 'unknown'),
            ('timeout is not semantic absence', {'clear_code': -25204}, 'unknown'),
            ('malformed attribute refuses', {'element_type': False}, 'invalid'),
            ('wrong role refuses', {'role': 'AXTextField'}, 'invalid')]
for flag in ['same_pid', 'parent_is_search', 'enabled', 'press_action']:
    bindings.append((flag + ' false refuses semantic Clear', {flag: False}, 'invalid'))
for field in ['pid_code', 'parent_code', 'role_code', 'enabled_code', 'actions_code']:
    bindings.append((field + ' error refuses semantic Clear', {field: -25204}, 'invalid'))

checks, failures = [], []
for name, changes, expected in cases + bindings:
    try:
        defaults = binding if (name, changes, expected) in bindings else base
        run = subprocess.run([a.helper, '--policy-test'], input=json.dumps({**defaults, **changes}) + '\n',
                             text=True, capture_output=True, timeout=5)
        result = json.loads(run.stdout) if run.stdout else {'exit_status': run.returncode}
        ok = run.returncode == 0 and result.get('result') == expected and result.get('apple_accessed') is False
    except Exception as e:
        ok, result = False, {'error': type(e).__name__}
    checks.append({'name': name, 'passed': ok, 'expected': expected, 'result': result})
    if not ok:
        failures.append(name)
report = {'passed': not failures, 'checks': checks, 'failures': failures,
          'command': shlex.join(['python3', str(pathlib.Path(__file__).resolve()), '--helper', str(pathlib.Path(a.helper).resolve()), '--report', str(pathlib.Path(a.report).resolve())]),
          'helper_sha256': hashlib.sha256(pathlib.Path(a.helper).read_bytes()).hexdigest(),
          'boundary': 'isolated native early recovery decision; existing clear model proof remains separate; no Apple/UI/auth/delete',
          'apple_accessed': False, 'customer_records_modified': 0}
pathlib.Path(a.report).write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'passed': report['passed'], 'checks': len(checks), 'failures': len(failures)}))
raise SystemExit(0 if report['passed'] else 1)
