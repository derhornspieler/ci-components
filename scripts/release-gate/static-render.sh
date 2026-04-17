#!/usr/bin/env bash
# static-render.sh — Gate #1.
#
# Cheap static validation. Runs on every MR in <30s without any Vault,
# network, or catalog dependency. Catches:
#   - YAML parse errors in any template
#   - missing spec.inputs declarations
#   - jobs without tags: (would sit pending in our cluster forever)
#   - $[[ inputs.X ]] references where X is not declared in this
#     template's spec.inputs (the v4.0.5 scope bug)
#
# Catalog-resolution issues (directory naming, chain-include version
# drift, hidden-component visibility) belong in Gate #2, which uses an
# ephemeral rc tag against the real catalog URL — branch-ref linting
# doesn't work because GitLab's catalog only resolves component URLs
# by published tag.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"

python3 - "${root}" <<'PY'
import re, sys, pathlib
from ruamel.yaml import YAML

root = pathlib.Path(sys.argv[1])
y = YAML(typ='safe')
y.constructor.add_constructor('!reference', lambda l, n: ['_REF_'])

errors = 0
total = 0
for p in sorted((root / "templates").rglob("template.yml")):
    total += 1
    raw = p.read_text()

    # 1) Multi-doc YAML parses
    try:
        docs = list(y.load_all(raw))
    except Exception as e:
        print(f"FAIL parse {p.relative_to(root)}: {e}")
        errors += 1
        continue

    spec = next((d for d in docs if isinstance(d, dict) and 'spec' in d), {}).get('spec', {}) or {}
    body = next((d for d in docs if isinstance(d, dict) and 'spec' not in d), {}) or {}
    declared_inputs = set((spec.get('inputs') or {}).keys())

    # 2) Every $[[ inputs.X ]] reference must be declared in THIS template's spec.inputs
    # Skip comment lines (start with optional whitespace + '#') so caller-pattern
    # docstrings don't trip the check.
    code_lines = [ln for ln in raw.splitlines() if not re.match(r'^\s*#', ln)]
    referenced = set(re.findall(r'\$\[\[\s*inputs\.(\w+)', "\n".join(code_lines)))
    missing = referenced - declared_inputs
    if missing:
        print(f"FAIL inputs {p.relative_to(root)}: references undeclared inputs: {sorted(missing)}")
        errors += 1

    # 3) Every job (top-level key with `stage:`) must declare tags:
    if isinstance(body, dict):
        for job_name, job in body.items():
            if not isinstance(job, dict):
                continue
            if job_name.startswith('.'):  # anchors
                continue
            if 'stage' in job and 'tags' not in job:
                print(f"FAIL tags {p.relative_to(root)}: job {job_name!r} has no tags: (would sit pending)")
                errors += 1

print(f"\n[static-render] {total} templates checked, {errors} failures")
sys.exit(0 if errors == 0 else 1)
PY
