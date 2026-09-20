"""Explicitly migrate copied, known-origin fixture manifests; never originals."""
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from generation import generation
from manifest_binding import BIND_FIELDS, bind_digest


def adopt_fixture(root, names):
    mods = Path(root) / 'modules'
    base = json.loads((mods / 'base.json').read_text())
    for name in names:
        path = mods / (name + '.json')
        assert not path.is_symlink(), 'fixture must own a copied manifest'
        doc = json.loads(path.read_text())
        doc['generation'] = generation(doc['snapshot'], doc['suite'], doc['arch'], base['artifact']['sha256'])
        doc['binding']['fields'] = list(BIND_FIELDS)
        doc['binding']['fields_sha256'] = bind_digest(doc)
        path.write_text(json.dumps(doc))
