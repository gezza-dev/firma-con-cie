# SPDX-License-Identifier: BSD-3-Clause
"""Locate verified development test tools outside a production distribution."""
import hashlib
import json


def test_tools_runtime(runtime, external=None):
    if external is None:
        return runtime
    external = external.resolve()
    manifest = json.loads((external / 'backend-manifest.json').read_text(encoding='utf-8'))
    for name, digest in manifest['files'].items():
        if name.startswith(('tests/', 'ltv/tests/')):
            if hashlib.sha256((external / name).read_bytes()).hexdigest() != digest:
                raise ValueError('External test tool checksum mismatch: ' + name)
    return external
