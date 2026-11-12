"""Fail-closed prerequisite gate for PHP/ALL completion claims.

An initial inventory, historical counts, an empty requirement set, or a merely
successful process must never make this gate pass. This checks evidence records;
it is not a substitute for implementing or independently reviewing semantics.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def inspect(matrix: dict, root: Path, stage: int) -> dict:
    errors: list[str] = []
    if matrix.get('exhaustive') is not True:
        errors.append('The requirements inventory has not been established as exhaustive.')
    if matrix.get('inventory_gaps'):
        errors.append('Unresolved inventory gaps remain.')
    target = matrix.get('target', {})
    if target.get('php_version') != '8.5.12':
        errors.append('The approved PHP target is not fixed to 8.5.12.')
    approved = target.get('stage1', {})
    for field in ('language', 'cli', 'web', 'standard_extensions', 'existing_native_extension_binaries'):
        if approved.get(field) is not True:
            errors.append(f'Approved stage-1 requirement omitted: {field}.')
    selected = [r for r in matrix.get('requirements', [])
                if r.get('stage') == stage and r.get('kind') == 'leaf'
                and r.get('required', True)]
    other_required = [r for r in matrix.get('requirements', [])
                      if r.get('stage') == stage and r.get('kind') != 'leaf'
                      and r.get('required', True)]
    for requirement in other_required:
        rid = requirement.get('id', '<missing id>')
        if requirement.get('kind') not in ('aggregate', 'control'):
            errors.append(f'{rid}: unknown requirement kind.')
        if requirement.get('state') != 'VERIFIED':
            errors.append(f'{rid}: required {requirement.get("kind")} is not VERIFIED.')
        if requirement.get('kind') == 'aggregate':
            if not any(r.get('parent_id') == rid for r in matrix.get('requirements', [])):
                errors.append(f'{rid}: aggregate has not been expanded into auditable requirements.')
    if not selected:
        errors.append(f'No required stage-{stage} leaf requirements were recorded.')
    ids = [r.get('id') for r in selected]
    if None in ids or len(ids) != len(set(ids)):
        errors.append('Requirement IDs must be present and unique.')
    catalog = {e.get('id'): e for e in matrix.get('evidence_catalog', [])}
    for requirement in selected:
        rid = requirement.get('id', '<missing id>')
        if requirement.get('state') != 'VERIFIED':
            errors.append(f'{rid}: state is {requirement.get("state", "MISSING")}.')
            continue
        if not requirement.get('sources') or not requirement.get('tests'):
            errors.append(f'{rid}: official sources and test references are required.')
        refs = requirement.get('evidence_refs', [])
        if not refs:
            errors.append(f'{rid}: no verification evidence.')
        for reference in refs:
            entry = catalog.get(reference)
            if not entry:
                errors.append(f'{rid}: missing evidence record {reference}.')
                continue
            contract = entry.get('verification', {})
            if (contract.get('php_version') != '8.5.12'
                    or contract.get('complete_for_requirement') is not True
                    or contract.get('actual_execution') is not True
                    or contract.get('passed', 0) <= 0
                    or any(contract.get(field) != 0 for field in ('failed', 'unexecuted', 'skipped'))):
                errors.append(f'{rid}: {reference} lacks a complete, executed target-specific verification contract.')
            path = entry.get('path')
            digest = entry.get('sha256')
            if not path or not digest:
                errors.append(f'{rid}: {reference} needs a concrete artifact and SHA-256.')
                continue
            artifact = (root / path).resolve()
            if not artifact.is_relative_to(root.resolve()) or not artifact.is_file():
                errors.append(f'{rid}: evidence artifact is absent or outside the repository: {path}.')
            elif hashlib.sha256(artifact.read_bytes()).hexdigest().lower() != str(digest).lower():
                errors.append(f'{rid}: evidence artifact hash mismatch: {path}.')
    # Final acceptance is separate from technical testing, as required by AC-12.
    acceptance = matrix.get('owner_acceptance', {})
    if acceptance.get(f'stage{stage}') is not True:
        errors.append(f'Owner final acceptance for stage {stage} is not recorded.')
    if stage == 2 and acceptance.get('stage1') is not True:
        errors.append('Stage 1 must be completed and accepted before stage 2.')
    return {
        'stage': stage, 'status': 'PREREQUISITES_MET' if not errors else 'NOT_COMPLETE',
        'PHP_FULL_COMPATIBLE': stage == 1 and not errors,
        'required_leaf_count': len(selected), 'errors': errors,
        'note': 'Artifact checks do not prove semantic completeness or authenticate owner sign-off.',
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--matrix', type=Path, required=True)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--stage', type=int, choices=(1, 2), default=1)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    matrix = json.loads(args.matrix.read_text(encoding='utf-8-sig'))
    result = inspect(matrix, args.root, args.stage)
    text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        if args.output.exists():
            parser.error('Refusing to overwrite an existing gate result.')
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding='utf-8')
    print(text, end='')
    return 0 if not result['errors'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
