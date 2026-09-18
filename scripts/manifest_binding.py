"""Schema-1 manifest integrity policy shared by extractor and consumers.

Digests detect drift, not malicious resealing. Required coverage and required
sidecar seals are consumer policy: the document cannot opt out of either.
"""
import hashlib
import json
import re
import subprocess

BIND_FIELDS = ['module', 'version', 'parent', 'snapshot', 'suite', 'arch',
               'requires', 'conflicts', 'provides', 'requested', 'removed',
               'uid_range', 'accounts', 'units', 'artifact', 'packages']


def bind_digest(doc, fields=BIND_FIELDS):
    payload = {key: doc.get(key) for key in fields}
    return hashlib.sha256(json.dumps(payload, sort_keys=True,
                                     separators=(',', ':'),
                                     ensure_ascii=True).encode('utf-8')).hexdigest()


def validate_manifest(doc):
    """Raise ValueError for missing, unsupported or inconsistent binding."""
    b = doc.get('binding')
    if not isinstance(b, dict):
        raise ValueError('manifest carries no binding')
    if doc.get('schema') != 1 or b.get('schema') != 1:
        raise ValueError('unsupported manifest or binding schema')
    if b.get('fields') != BIND_FIELDS or any(k not in doc for k in BIND_FIELDS):
        raise ValueError('binding does not cover all required schema-1 fields')
    for key in ('fields_sha256', 'artifact_sha256', 'sidecar_sha256'):
        digest = b.get(key)
        if not isinstance(digest, str) or not re.fullmatch('[0-9a-f]{64}', digest):
            raise ValueError('missing or malformed binding.' + key)
    if bind_digest(doc) != b['fields_sha256']:
        raise ValueError('a bound field was edited or removed since extraction')
    art = doc.get('artifact')
    if not isinstance(art, dict) or b['artifact_sha256'] != art.get('sha256'):
        raise ValueError('binding names a different artefact digest')
    if b.get('source') != 'artifact':
        raise ValueError('manifest was not derived from the artefact')


def load_sidecar(doc, path, module):
    """Check the mandatory seal before parsing/using class-4 ownership data."""
    validate_manifest(doc)
    try:
        raw = subprocess.run(['zstd', '-dcq', str(path)],
                             capture_output=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ValueError('cannot read class-4 sidecar: %s' % exc) from exc
    if hashlib.sha256(raw).hexdigest() != doc['binding']['sidecar_sha256']:
        raise ValueError('SIDECAR DIGEST MISMATCH')
    try:
        side = json.loads(raw)
    except (ValueError, UnicodeError) as exc:
        raise ValueError('invalid sidecar JSON') from exc
    if not isinstance(side, dict) or side.get('schema') != 1 or side.get('module') != module:
        raise ValueError('sidecar module/schema mismatch')
    return side
