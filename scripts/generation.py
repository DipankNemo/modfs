"""One generation is one archive view and one exact base artefact.

Module specs are deliberately absent: they may change within a generation.
This is an integrity identifier, not a signature or an atomic publisher.
"""
import hashlib
import json
import re


def generation(snapshot, suite, arch, base_sha256):
    if not isinstance(base_sha256, str) or not re.fullmatch('[0-9a-f]{64}', base_sha256):
        raise ValueError('generation needs a base SHA256')
    if not isinstance(snapshot, str) or not re.fullmatch(r'\d{8}T\d{6}Z', snapshot):
        raise ValueError('generation needs a snapshot')
    if not suite or not arch:
        raise ValueError('generation needs suite and architecture')
    fields = dict(snapshot=snapshot, suite=suite, arch=arch, base_sha256=base_sha256)
    digest = hashlib.sha256(json.dumps(fields, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    return dict(id=digest, **fields)


def validate_generation(doc):
    g = doc.get('generation')
    if not isinstance(g, dict):
        raise ValueError('missing generation; rebuild or explicitly adopt a verified legacy catalogue')
    expected = generation(doc.get('snapshot'), doc.get('suite'), doc.get('arch'), g.get('base_sha256'))
    if g != expected:
        raise ValueError('inconsistent generation identity')
    if doc.get('parent') is None and g['base_sha256'] != (doc.get('artifact') or {}).get('sha256'):
        raise ValueError('base generation names a different base artefact')


def extraction_generation(doc, previous, base_sha256, new_build=False, adopt=False):
    """A refresh must never relabel an old delta against today's base."""
    expected = generation(doc['snapshot'], doc['suite'], doc['arch'], base_sha256)
    if doc['parent'] is None or new_build:
        return expected
    old = previous.get('generation')
    if old is None:
        if not adopt:
            raise ValueError('legacy module has no generation; rebuild or use --adopt-generation after verifying its origin')
        return expected
    if old != expected:
        raise ValueError('generation changed during metadata refresh; rebuild the module against this base')
    return old
