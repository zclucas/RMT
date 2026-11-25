"""Repair the exact v1.2 resources accidentally removed by the retirement CI."""
import hashlib
import json
from urllib.request import Request, urlopen
import zipfile

import sync_gitcode_assets as mirror

ORIGINAL_ZIP = 'https://github.com/zclucas/RMT/releases/download/RMTv1.2/RMTv1.2_x64.zip'
ZIP_SHA = '87ce64523a65a01ad94f13fbbe5abf5002c3b14df32f93513f4144110cdae0cf'
ORIGINALS = {
    'CountDown.exe': (1281024, '350ac310d2440f4fc2a18f4ffe7a1f465b6a40643ffdb3ad3ea09ec751a17d71'),
    'PlayAudio.vbs': (631, 'd1e2a38996a27bdeaefbb080f6244cf2d03c41bc5d294e9f14e07d160af1f967'),
    'Xbox.png': (65156, '270ecc36ae8c14c46979de0c369f2edc42778809872d9efc90d3201598b13cfb'),
}
CATALOG_SHA = {
    'v1.2_x64': '0a6665c9070cb499ffab9109f712cc1a831d8183f7d410aa71b822288e4a4281',
    'v1.2_x86': '3b5c33d1d65e7c6ba7cc7a9dfc30529167933c80b7d8d5448ad2845e2e7aedd3',
}


def restore_resources(store, catalog_name):
    source = store.directory / 'original-v1.2.zip'
    with urlopen(Request(ORIGINAL_ZIP, headers={'User-Agent': 'RMT-stable-repair'}), timeout=90) as response:
        source.write_bytes(response.read(60 * 1024 * 1024 + 1))
    if mirror.sha(source) != 'sha256:' + ZIP_SHA:
        raise ValueError('Original release ZIP checksum mismatch')
    staged = {}
    with zipfile.ZipFile(source) as archive:
        for name, (size, digest) in ORIGINALS.items():
            matches = [i for i in archive.infolist() if i.file_size == size and not i.is_dir()
                       and hashlib.sha256(archive.read(i)).hexdigest() == digest]
            if len(matches) != 1:
                raise ValueError('Missing or ambiguous original bytes: ' + name)
            path = store.directory / name
            path.write_bytes(archive.read(matches[0]))
            staged[name] = path
    catalogs = {}
    # Validate BOTH full reconstructed inventories against pre-cleanup snapshots
    # before any write. No unrelated record or existing file may be replaced.
    for tag, expected in CATALOG_SHA.items():
        catalog = store.catalog(tag)
        if not catalog:
            raise ValueError('Missing repair inventory: ' + tag)
        for name, (size, digest) in ORIGINALS.items():
            entry = dict(scope=tag, name=name, size=size, sha256=digest, purpose='共享资源')
            if name in catalog['assets'] and catalog['assets'][name] != entry:
                raise ValueError('Original resource pin changed: ' + tag + '/' + name)
            existing = store.asset(tag, name)
            if existing and (existing['size'] != size or existing.get('digest') != 'sha256:' + digest):
                raise ValueError('Existing stable file differs: ' + tag + '/' + name)
            catalog['assets'][name] = entry
        # Preserve the original inventory's order (including its punctuation
        # collation); insert the missing records at their original anchors.
        entries = catalog['assets']
        ordered = {}
        for name, entry in entries.items():
            anchor = {'End.wav': 'CountDown.exe', 'ppocr_keys_v1.txt': 'PlayAudio.vbs'}.get(name)
            if anchor:
                ordered[anchor] = entries[anchor]
            if name not in ORIGINALS:
                ordered[name] = entry
        ordered['Xbox.png'] = entries['Xbox.png']
        catalog['assets'] = ordered
        path = store.directory / (tag + '-restored-catalog.json')
        path.write_bytes((json.dumps(catalog, ensure_ascii=True, indent=2) + '\n').encode('utf-8'))
        if mirror.sha(path) != 'sha256:' + expected:
            raise ValueError('Reconstructed inventory differs from original: ' + tag)
        catalogs[tag] = path
    restored = []
    for tag, catalog in catalogs.items():
        for name, path in staged.items():
            store.put(tag, name, path)
            restored.append([tag, name])
        # The only inventory change is adding back three original pinned records.
        store.put(tag, catalog_name, catalog, replace=True)
    return dict(status='passed', restored_attachments=restored,
                original_catalog_sha256=CATALOG_SHA)
