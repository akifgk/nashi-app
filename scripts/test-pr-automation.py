#!/usr/bin/env python3
"""Offline policy regression checks; a small model, NOT Mergify's live simulator.

Requires PyYAML. Optional official-schema validation also requires jsonschema:
python scripts/test-pr-automation.py --schema-dir /path/to/downloaded/schemas
No repository scripts, shell commands, credentials or network calls are executed.
"""
import argparse
import json
from pathlib import Path
import re
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
CR = yaml.safe_load((ROOT / '.coderabbit.yaml').read_text(encoding='utf-8'))
MG = yaml.safe_load((ROOT / '.mergify.yml').read_text(encoding='utf-8'))
REQUIRED = {'security', 'mac-source', 'windows'}


def snapshot(**changes):
    value = dict(base='main', draft=False, conflict=False, **{'from-fork': False},
                 files=['docs/testing/example.md'], checks=REQUIRED.copy(),
                 sender='orkunisitmak', **{'sender-permission': 'admin'},
                 labels=[], approvals=[], lines=1)
    value.update(changes)
    return value


def condition_matches(expression, pr):
    """Model only the operators used here; reject unsupported expressions."""
    negative = expression.startswith('-')
    expression = expression[1:] if negative else expression
    if '~=' in expression:
        key, pattern = expression.split('~=', 1)
        if key != 'files':
            raise ValueError('Unsupported regex attribute: ' + key)
        result = any(re.search(pattern, path) is not None for path in pr['files'])
    elif expression.startswith('#files'):
        match = re.fullmatch(r'#files([<>])([0-9]+)', expression)
        if not match:
            raise ValueError('Unsupported numeric condition')
        count = len(pr['files'])
        result = count < int(match[2]) if match[1] == '<' else count > int(match[2])
    elif '=' in expression:
        key, value = expression.split('=', 1)
        result = value in pr['checks'] if key == 'check-success' else pr[key] == value
    elif expression in {'draft', 'conflict', 'from-fork'}:
        result = pr[expression]
    else:
        raise ValueError('Unsupported condition: ' + expression)
    return not result if negative else result


def matches(rule, pr):
    return all(condition_matches(item, pr) for item in rule['conditions'])


class AutomationPolicyTests(unittest.TestCase):
    def test_no_workflow_action_can_write_or_merge(self):
        self.assertEqual(set(MG), {'pull_request_rules', 'commands_restrictions'})
        self.assertEqual(len(MG['pull_request_rules']), 4)
        for rule in MG['pull_request_rules']:
            self.assertEqual(rule['actions'], {}, rule['name'])

    def test_markdown_observation_allow_and_deny(self):
        rule = MG['pull_request_rules'][3]
        cases = [
            ('documentation', {}, True),
            ('root readme', {'files': ['README.md', 'README.tr.md']}, True),
            ('fork', {'from-fork': True}, False),
            ('draft', {'draft': True}, False),
            ('conflict', {'conflict': True}, False),
            ('empty change', {'files': []}, False),
            ('missing check', {'checks': {'security', 'windows'}}, False),
            ('failed or pending check', {'checks': set()}, False),
            ('other base', {'base': 'release'}, False),
            ('docs script', {'files': ['docs/assets/playground.js']}, False),
            ('source mixed in', {'files': ['README.md', 'Sources/NashiCore/Models.swift']}, False),
            ('workflow', {'files': ['.github/workflows/source.yml']}, False),
            ('dependency', {'files': ['Package.resolved']}, False),
            ('automation config', {'files': ['.mergify.yml']}, False),
            ('rename outside allowlist', {'files': ['README.md', 'scripts/old.md']}, False),
        ]
        for name, fields, expected in cases:
            with self.subTest(name=name):
                self.assertEqual(matches(rule, snapshot(**fields)), expected)

    def test_sensitive_paths_observed(self):
        rule = MG['pull_request_rules'][2]
        for path in ['.github/workflows/source.yml', '.mergify.yml', '.coderabbit.yaml',
                     'Configuration/Updates.plist', 'scripts/build-app.sh',
                     'Sources/NashiUpdates/AppUpdater.swift',
                     'Sources/TangerineUpdates/UpdateCredentialBrokerProtocol.swift',
                     'Sources/UpdateCredentialBroker/main.swift',
                     'Sources/NashiCore/ProcessRunner.swift', 'Package.swift',
                     'windows/Nashi.Core/packages.lock.json',
                     'windows/Nashi.Core/Nashi.Core.csproj', 'windows/Directory.Build.props']:
            with self.subTest(path=path):
                self.assertTrue(matches(rule, snapshot(files=[path])))

    def test_labels_approvals_and_small_diffs_never_authorize_actions(self):
        for actor in ['orkunisitmak', 'outside-contributor', 'coderabbitai[bot]', 'dependabot[bot]']:
            for approvals in [[], ['coderabbitai[bot]'], ['orkunisitmak@old-sha']]:
                pr = snapshot(sender=actor, labels=['bug', 'safe-to-merge', 'approved'],
                              approvals=approvals, lines=1)
                for rule in MG['pull_request_rules']:
                    if matches(rule, pr):
                        self.assertFalse(rule['actions'])

    def test_mutating_comment_commands_denied_even_to_owner(self):
        commands = MG['commands_restrictions']
        self.assertEqual(set(commands), {'backport', 'copy', 'dequeue', 'queue',
                                       'requeue', 'rebase', 'squash', 'update', 'refresh'})
        for sender in ['orkunisitmak', 'outside-contributor', 'mergify[bot]']:
            for count in [0, 1, 100]:
                for name, rule in commands.items():
                    if name != 'refresh':
                        with self.subTest(sender=sender, count=count, command=name):
                            self.assertFalse(matches(rule, snapshot(sender=sender, files=['README.md'] * count)))
        self.assertTrue(matches(commands['refresh'], snapshot()))
        self.assertFalse(matches(commands['refresh'], snapshot(sender='outside-contributor')))
        self.assertFalse(matches(commands['refresh'], snapshot(**{'sender-permission': 'read'})))

    def test_coderabbit_review_only(self):
        reviews = CR['reviews']
        self.assertFalse(CR['inheritance'])
        self.assertFalse(reviews['auto_approvals']['enabled'])
        self.assertFalse(reviews['auto_approvals']['allow_author_approval'])
        self.assertFalse(reviews['request_changes_workflow'])
        self.assertFalse(reviews['auto_apply_labels'])
        self.assertEqual(reviews['post_merge_actions'], [])
        for value in reviews['finishing_touches'].values():
            self.assertFalse(value.get('enabled', True) if isinstance(value, dict) else value)
        self.assertTrue(reviews['auto_review']['auto_incremental_review'])
        self.assertFalse(reviews['auto_review']['drafts'])
        self.assertFalse(CR['issue_enrichment']['planning']['enabled'])
        self.assertFalse(CR['issue_enrichment']['labeling']['auto_apply_labels'])


def validate_schemas(directory):
    import jsonschema
    for name, value in [('coderabbit', CR), ('mergify', MG)]:
        schema = json.loads((directory / (name + '.json')).read_text(encoding='utf-8'))
        validator = jsonschema.validators.validator_for(schema)
        validator.check_schema(schema)
        validator(schema).validate(value)
        print('PASS official JSON Schema:', name, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--schema-dir', type=Path)
    args, remaining = parser.parse_known_args()
    if args.schema_dir:
        validate_schemas(args.schema_dir)
    unittest.main(argv=[__file__] + remaining)
