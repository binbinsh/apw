#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Exercise background index routing and current full-frame absence gates."""
import argparse, hashlib, json, pathlib, shlex, subprocess

p = argparse.ArgumentParser()
p.add_argument('--helper', required=True)
p.add_argument('--report', required=True)
a = p.parse_args()
target = {'title': 'apw-absence-target.invalid', 'username': ''}
current = [['apw-absence-target.invalid'], ['apw-other-current.invalid']]
cached = [['apw-cached-old.invalid'], ['apw-other-current.invalid']]
good = {'complete': True, 'query_empty': True, 'category_matches': True,
        'owner_unchanged': True, 'window_bound': True, 'raw_count': 2,
        'published_count': 2, 'labels': cached}

def frame(**changes):
    return {**good, **changes}

def replay(frames, key=None):
    return {'operation': 'full-index-absence', 'key': key or target,
            'frames': frames, 'cached_labels': cached}

cases = [
    ('background ignores writable AXValue', {'operation': 'query', 'background': True, 'value_settable': True}, 'unfiltered-index'),
    ('background ignores writable selected text', {'operation': 'query', 'background': True, 'range_settable': True, 'text_settable': True}, 'unfiltered-index'),
    ('foreground selected text route remains', {'operation': 'query', 'background': False, 'range_settable': True, 'text_settable': True}, 'selected-text'),
    ('foreground value route remains', {'operation': 'query', 'background': False, 'value_settable': True}, 'witnessed-value'),
    ('same-count cloud replacement finds target', replay([frame(labels=current), frame(labels=current)]), 'present'),
    ('stable current full frames prove absence', replay([frame(), frame()]), 'absent'),
    ('one fresh frame cannot prove absence', replay([frame()]), 'hold'),
    ('same count with changed membership cannot prove absence', replay([frame(), frame(labels=[['apw-new-current.invalid'], ['apw-other-current.invalid']])]), 'hold'),
    ('same count with reordered rows cannot prove absence', replay([frame(), frame(labels=list(reversed(cached)))]), 'hold'),
    ('missing row labels refuses', replay([frame(labels=[cached[0]]), frame(labels=[cached[0]])]), 'hold'),
    ('zero raw with positive published count refuses', replay([frame(raw_count=0, labels=[]), frame(raw_count=0, labels=[])]), 'hold'),
    ('zero raw with unknown published count refuses', replay([frame(raw_count=0, published_count=-1, labels=[]), frame(raw_count=0, published_count=-1, labels=[])]), 'hold'),
    ('proved current empty inventory can prove absence', replay([frame(raw_count=0, published_count=0, labels=[]), frame(raw_count=0, published_count=0, labels=[])]), 'absent'),
    ('overbound inventory refuses', replay([frame(raw_count=3001), frame(raw_count=3001)]), 'hold'),
    ('requested account appears in stable current inventory', replay([frame(labels=[['apw-absence-target.invalid', 'wanted@example.invalid'], ['other']])]*2, {'title': target['title'], 'username': 'wanted@example.invalid'}), 'present'),
    ('different account does not match requested identity', replay([frame(labels=[['apw-absence-target.invalid', 'other@example.invalid'], ['other']])]*2, {'title': target['title'], 'username': 'wanted@example.invalid'}), 'absent'),
    ('incomplete prior frame permits later independent complete pair', replay([frame(complete=False), frame(), frame()]), 'absent'),
    ('published generation changed refuses pair', replay([frame(), frame(published_count=3)]), 'hold'),
]
for flag in ['complete', 'query_empty', 'category_matches', 'owner_unchanged', 'window_bound']:
    cases.append((flag + ' false resets pair', replay([frame(), frame(**{flag: False}), frame()]), 'hold'))

ready = {'operation': 'search-clear-route', 'background': True, 'complete': True,
         'query_empty': True, 'category_matches': True, 'owner_unchanged': True,
         'raw_count': 2, 'published_count': 2, 'cached_raw_count': -1, 'model_needs_proof': False}
cases += [
    ('readable All starts without search mutation', ready, 'ready'),
    ('background filtered model holds without setter', {**ready, 'query_empty': False}, 'hold'),
    ('background zero model holds without recovery', {**ready, 'raw_count': 0}, 'hold'),
    ('background unknown dirty model holds without recovery', {**ready, 'model_needs_proof': True}, 'hold'),
    ('foreground retains bounded recovery route', {**ready, 'background': False, 'raw_count': 0}, 'recover'),
]
for cached_category in ['', 'active', 'deleted']:
    cases += [
        ('actual complete category true binds without press ' + repr(cached_category),
         {'operation': 'category-selection-route', 'cached_category': cached_category,
          'complete': True, 'actual_matches': True}, 'bind'),
        ('actual complete category false permits addressed navigation ' + repr(cached_category),
         {'operation': 'category-selection-route', 'cached_category': cached_category,
          'complete': True, 'actual_matches': False}, 'navigate'),
        ('incomplete category never navigates ' + repr(cached_category),
         {'operation': 'category-selection-route', 'cached_category': cached_category,
          'complete': False, 'actual_matches': True}, 'hold'),
    ]
cases += [
    ('unknown category never navigates', {'operation': 'category-selection-route', 'complete': True}, 'hold'),
]

def model_pair(first=None, second=None, **changes):
    return {'operation': 'category-model-pair', 'first': first or frame(labels=[]),
            'second': second or frame(labels=[]), 'references_same': True, **changes}

cases += [
    ('two complete unchanged structural frames permit index', model_pair(), True),
    ('same count but replacement row refuses structural pair', model_pair(references_same=False), False),
    ('changed published category generation refuses structural pair', model_pair(second=frame(labels=[], published_count=3)), False),
    ('changed raw count refuses structural pair', model_pair(second=frame(labels=[], raw_count=3)), False),
    ('zero rows positive published category refuses structural pair', model_pair(frame(labels=[], raw_count=0), frame(labels=[], raw_count=0)), False),
    ('zero rows unknown published category refuses structural pair', model_pair(frame(labels=[], raw_count=0, published_count=-1), frame(labels=[], raw_count=0, published_count=-1)), False),
    ('complete genuinely empty model permits structural pair', model_pair(frame(labels=[], raw_count=0, published_count=0), frame(labels=[], raw_count=0, published_count=0)), True),
]
for flag in ['complete', 'query_empty', 'category_matches', 'owner_unchanged', 'window_bound']:
    cases.append((flag + ' false refuses structural pair', model_pair(second=frame(labels=[], **{flag: False})), False))
# Isolated failure specification for the known-inventory lower bound: a stable
# nonempty residual subset cannot prove full-library absence, while additional
# structural rows must not force equality with the displayed account count.
short_model = frame(raw_count=15, published_count=2018,
                    labels=[['apw-short-model-%d.invalid' % i] for i in range(15)])
structural_rows = frame(raw_count=7, published_count=2,
                        labels=[['apw-full-model-%d.invalid' % i] for i in range(7)])
cases += [
    ('known inventory larger than stable residual model holds', replay([short_model, short_model]), 'hold'),
    ('extra structural rows do not require raw published equality', replay([structural_rows, structural_rows]), 'absent'),
]
checks, failures = [], []
for name, q, expected in cases:
    try:
        run = subprocess.run([a.helper, '--policy-test'], input=json.dumps(q) + '\n', text=True, capture_output=True, timeout=5)
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
          'legacy_counterexample': {'cached_count': 2, 'current_count': 2, 'cached_target_matches': 0, 'current_target_matches': 1,
                                    'source': 'selectCategory cached count reuse followed by readKey cached matches.count>0 requirement',
                                    'boundary': 'static deterministic counterexample, not an Apple run'},
          'boundary': 'early native strategy/current complete-index reducer; not Apple acceptance',
          'apple_accessed': False, 'customer_records_modified': 0}
pathlib.Path(a.report).write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'passed': report['passed'], 'checks': len(checks), 'failures': len(failures)}))
raise SystemExit(0 if report['passed'] else 1)
