#!/usr/bin/env python3
"""Read-only diagnostics; never emits passwords or private key material.

Usage: content_probe.py ARTIFACT_DIR cross-machine-differences.json.gz
"""
import datetime as dt
import gzip
import hashlib
import io
import json
from pathlib import Path
import struct
import subprocess as sp
import sys

root = Path(sys.argv[1])
differences = json.load(gzip.open(sys.argv[2], 'rt'))
out = {}

def read(module, name):
    return sp.check_output(['unsquashfs', '-cat', str(root / (module + '.sqsh')), name])

for module in ('base', 'memcached', 'mta-msmtp', 'redis', 'tcpdump', 'mysql', 'postgres'):
    out[module] = {}
    for name in ('etc/shadow', 'etc/shadow-'):
        # Preserve a digest of all other fields for equality checks, never their values.
        rows = []
        for line in read(module, name).decode().splitlines():
            fields = line.split(':')
            rows.append({'account': fields[0], 'last_change_day': fields[2],
                         'other_fields_sha256': hashlib.sha256(':'.join(fields[:2] + fields[3:]).encode()).hexdigest()})
        out[module][name] = rows

out['text'] = {}
for module, names in {
    'emacs': ['usr/share/info/dir', 'usr/share/info/dir.old', 'usr/sbin/update-info-dir'],
    'mta-nullmailer': ['etc/mailname', 'var/cache/debconf/config.dat', 'var/lib/dpkg/info/nullmailer.config'],
    'java': ['var/lib/dpkg/info/openjdk-11-jre-headless:amd64.postinst', 'var/lib/dpkg/info/ca-certificates-java.postinst'],
    'postgres': ['var/lib/dpkg/info/postgresql-14.postinst', 'usr/bin/pg_createcluster', 'usr/sbin/make-ssl-cert'],
    'mysql': ['var/lib/dpkg/info/mariadb-server-10.6.postinst', 'usr/bin/mariadb-install-db'],
}.items():
    for name in names:
        out['text'][module + ':' + name] = read(module, name).decode(errors='replace')

# The Java trust store contains public certificates only. Parse its JKS entries.
data = read('java', 'etc/ssl/certs/java/cacerts')
buf = io.BytesIO(data)
def integer(fmt):
    return struct.unpack(fmt, buf.read(struct.calcsize(fmt)))[0]
def utf():
    return buf.read(integer('>H')).decode()
assert integer('>I') == 0xfeedfeed
assert integer('>I') == 2
certs = []
for _ in range(integer('>I')):
    assert integer('>I') == 2, 'Expected trusted certificate, not private key'
    alias = utf()
    millis = integer('>q')
    kind = utf()
    cert = buf.read(integer('>I'))
    certs.append({'alias': alias, 'created_ms': millis, 'certificate_type': kind,
                  'certificate_sha256': hashlib.sha256(cert).hexdigest()})
assert len(buf.read()) == 20
out['java_certificates'] = certs

out['pyc'] = {}
for name in differences['pipdemo']['changed']:
    if name.endswith('.pyc'):
        data = read('pipdemo', name)
        magic, flags, timestamp, size = struct.unpack('<4sIII', data[:16])
        out['pyc'][name] = {'magic': magic.hex(), 'flags': flags, 'timestamp': timestamp,
                            'source_size': size, 'payload_sha256': hashlib.sha256(data[16:]).hexdigest()}

cert = read('postgres', 'etc/ssl/certs/ssl-cert-snakeoil.pem')
out['postgres_public_certificate'] = sp.check_output(
    ['openssl', 'x509', '-noout', '-subject', '-serial', '-dates', '-fingerprint', '-sha256'], input=cert).decode()
control = read('postgres', 'var/lib/postgresql/14/main/global/pg_control')
out['postgres_system_identifier_le64'] = struct.unpack('<Q', control[:8])[0]
# No private key is read or emitted by this probe.
print(json.dumps(out, indent=2))
