"""Publish version catalogs and preserve shared dependencies before replacement.

All writers run under the rmt-resource-publication Actions concurrency group.
Catalogs are immutable; an archived logical filename overrides its shared copy.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import threading
import tarfile
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen
import zipfile

import sync_gitcode_assets as mirror

CATALOG = 'resources.json'
LEGACY_INDEX = 'resources.md'
ROOT = Path(__file__).resolve().parents[2]
POLICY = json.loads((ROOT / 'Scripts/ResourceLayout.json').read_text(encoding='utf-8-sig'))
VERSION_TAG = re.compile(r'^v(\d+(?:\.\d+)+)(?:F(\d+))?_(x64|x86)$')


def version_key(tag):
    match = VERSION_TAG.fullmatch(tag)
    if not match:
        raise ValueError('Invalid version resource tag: ' + tag)
    numbers = tuple(map(int, match[1].split('.')))
    return numbers + (0,) * (4 - len(numbers)) + (int(match[2]) if match[2] else 10**9,)


def managed_tag(tag):
    match = VERSION_TAG.fullmatch(tag)
    return bool(match and tuple(map(int, match[1].split('.'))) >= (1, 3))


def shared_name(name, arch):
    if name in POLICY.get("universal", []):
        return name
    stem, extension = os.path.splitext(name)
    return stem + '_' + arch + extension


def bundle_names():
    return POLICY.get('bundles', POLICY['versioned'] + POLICY['shared'])


def record(asset, scope, name=None):
    digest = asset.get('digest') or ''
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', digest) or asset['size'] <= 0:
        raise ValueError('Source has no verified digest: ' + asset['name'])
    return dict(scope=scope, name=name or asset['name'], size=asset['size'], sha256=digest[7:])


def metadata(name, entry):
    return dict(name=name, size=entry['size'], digest='sha256:' + entry['sha256'])


def purpose(name):
    logical = re.sub(r'_(x64|x86)(\.zip)$', r'\2', name)
    if logical.startswith('windows6.1-'):
        return 'Windows 7 系统补丁'
    return POLICY.get('purposes', {}).get(name, POLICY.get('purposes', {}).get(logical, '共享资源'))


def archive_files(path):
    if path.name.endswith('.zip'):
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            if len(names) != len(set(names)):
                raise ValueError('Duplicate archive entries')
            files = [dict(name=e.filename, size=e.file_size) for e in archive.infolist() if not e.is_dir()]
            if not files or any(item['size'] <= 0 for item in files):
                raise ValueError('Empty archive or file entry')
            return files
    if path.name.endswith(('.tar.bz2', '.tar.gz', '.tgz')):
        with tarfile.open(path) as archive:
            return [dict(name=e.name, size=e.size) for e in archive if e.isfile()]
    return []


def fingerprint(path):
    """Ignore ZIP timestamps; preserve the original archive bytes when entries match."""
    if not zipfile.is_zipfile(path):
        return mirror.sha(path)
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate ZIP entries')
        return sorted((item.filename, item.file_size,
                       hashlib.sha256(archive.read(item)).hexdigest())
                      for item in archive.infolist() if not item.is_dir())


class Store:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.verified = set()

    def releases(self):
        return [r for r in mirror.pages(mirror.gh, '/releases') if not r['draft']]

    def source(self, tag):
        return mirror.gh('/releases/tags/' + tag)

    def assets(self, tag):
        return mirror.pages(mirror.gh, '/releases/' + str(self.source(tag)['id']) + '/assets')

    def asset(self, tag, name):
        try:
            items = [a for a in self.assets(tag) if a['name'] == name]
        except HTTPError as exc:
            if exc.code == 404:
                return None
            raise
        if len(items) > 1:
            raise ValueError('Duplicate asset: ' + tag + '/' + name)
        return items[0] if items else None

    def ensure(self, tag):
        if not any(r['tag_name'] == tag for r in self.releases()):
            subprocess.run(['gh', 'release', 'create', tag, '--repo', 'zclucas/RMTAssets',
                            '--target', 'main', '--title', tag, '--notes', 'RMT ' + tag + ' resources',
                            '--latest=false'] + (['--prerelease'] if VERSION_TAG.fullmatch(tag) and 'F' in tag else []), check=True)
        mirror.ensure_release(self.source(tag))

    def download(self, tag, asset):
        directory = self.directory / tag
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / mirror.safe_name(asset['name'])
        if not path.exists() or path.stat().st_size != asset['size'] or mirror.sha(path) != asset['digest']:
            path, _ = mirror.download(tag, asset, directory)
        return path

    def catalog(self, tag):
        asset = self.asset(tag, CATALOG)
        if not asset:
            return None
        value = json.loads(self.download(tag, asset).read_text(encoding='utf-8'))
        if value.get('schema') != 1 or value.get('tag') != tag or not isinstance(value.get('assets'), dict):
            raise ValueError('Invalid catalog: ' + tag)
        return value

    def describe(self, tag, asset, scope=None, name=None):
        entry = record(asset, scope or tag, name)
        entry['purpose'] = purpose(asset['name'])
        if asset['name'].endswith(('.zip', '.tar.bz2', '.tar.gz', '.tgz')):
            entry['files'] = archive_files(self.download(tag, asset))
        return entry

    def model_descriptor(self, tag, entry):
        with urlopen(Request(mirror.public_url(tag, mirror.MODEL + '.parts.json'),
                             headers={'User-Agent': 'RMT-resource-layout'}), timeout=60) as response:
            raw = response.read(4 * 1024 * 1024 + 1)
        if len(raw) > 4 * 1024 * 1024:
            raise ValueError('Model descriptor too large')
        descriptor = json.loads(raw)
        if (descriptor.get('version') != 1 or descriptor.get('format') != 'lfs'
                or descriptor.get('name') != mirror.MODEL or descriptor.get('size') != entry['size']
                or descriptor.get('sha256') != entry['sha256']
                or descriptor.get('lfs_endpoint') != mirror.REMOTE + '/info/lfs/objects/batch'):
            raise ValueError('Model descriptor differs from pinned generation')
        return descriptor

    def verify_model(self, tag, entry):
        descriptor = self.model_descriptor(tag, entry)
        payload = dict(operation='download', transfers=['basic'],
                       objects=[dict(oid=entry['sha256'], size=entry['size'])])
        request = Request(descriptor['lfs_endpoint'], data=json.dumps(payload).encode(), method='POST',
                          headers={'Content-Type': 'application/vnd.git-lfs+json',
                                   'Accept': 'application/vnd.git-lfs+json'})
        with urlopen(request, timeout=60) as response:
            batch = json.load(response)
        objects = batch.get('objects') or []
        if len(objects) != 1 or objects[0].get('oid') != entry['sha256'] or objects[0].get('size') != entry['size']:
            raise ValueError('Pinned LFS object is absent')
        action = (objects[0].get('actions') or {}).get('download') or {}
        if urlsplit(action.get('href', '')).scheme != 'https':
            raise ValueError('No anonymous HTTPS download for pinned model')
        mirror.readback(tag, metadata(mirror.MODEL, entry), action['href'], action.get('header'))

    def verify(self, tag, name, entry):
        identity = (tag, name, entry['sha256'])
        if identity in self.verified:
            return
        source = self.asset(tag, name)
        if not source or source['size'] != entry['size'] or source.get('digest') != 'sha256:' + entry['sha256']:
            raise ValueError('GitHub asset differs: ' + tag + '/' + name)
        expected = metadata(name, entry)
        mirror.readback(tag, expected, source['browser_download_url'])
        if name == mirror.MODEL:
            self.verify_model(tag, entry)
        else:
            mirror.readback(tag, expected)
        self.verified.add(identity)

    def put(self, tag, name, path, replace=False):
        print('Publish {}/{}'.format(tag, name), flush=True)
        entry = dict(size=path.stat().st_size, sha256=mirror.sha(path)[7:])
        before = self.asset(tag, name)
        if before and (before['digest'] != 'sha256:' + entry['sha256'] or before['size'] != entry['size']):
            if not replace:
                raise ValueError('Refusing to overwrite immutable asset: ' + tag + '/' + name)
        self.ensure(tag)
        if not before or before['digest'] != 'sha256:' + entry['sha256']:
            # gh takes the local basename as the attachment name.
            staged = self.directory / 'upload' / tag / mirror.safe_name(name)
            staged.parent.mkdir(parents=True, exist_ok=True)
            if staged.resolve() != path.resolve():
                shutil.copyfile(path, staged)
            subprocess.run(['gh', 'release', 'upload', tag, str(staged), '--repo',
                            'zclucas/RMTAssets', '--clobber'], check=True)
        if name == mirror.MODEL:
            if tag == 'Common':
                model_dir = self.directory / 'lfs-update'
                model_dir.mkdir(exist_ok=True)
                mirror.try_lfs(path, metadata(name, entry), model_dir)
            else:
                # Archive the immutable LFS object ID, never a pointer to "latest".
                descriptor = dict(version=1, format='lfs', name=mirror.MODEL, size=entry['size'],
                                  sha256=entry['sha256'], lfs_endpoint=mirror.REMOTE + '/info/lfs/objects/batch')
                descriptor_path = self.directory / (tag + '-model.parts.json')
                descriptor_path.write_text(json.dumps(descriptor, indent=2), encoding='utf-8')
                mirror.upload(tag, descriptor_path,
                              dict(name=name + '.parts.json', size=descriptor_path.stat().st_size,
                                   digest=mirror.sha(descriptor_path)))
            self.verify_model(tag, entry)
        else:
            mirror.upload(tag, path, metadata(name, entry), max_time=600)
        source = self.asset(tag, name)
        if not source or source.get('digest') != 'sha256:' + entry['sha256'] or source['size'] != entry['size']:
            raise ValueError('Uploaded GitHub metadata differs')
        mirror.readback(tag, metadata(name, entry), source['browser_download_url'])
        self.verified.add((tag, name, entry['sha256']))
        entry['purpose'] = purpose(name)
        if name.endswith(('.zip', '.tar.bz2', '.tar.gz', '.tgz')):
            entry['files'] = archive_files(path)
        return entry

    def delete(self, tag, name):
        print('Retire {}/{}'.format(tag, name), flush=True)
        # Only exact filenames selected in the validated migration plan are removed.
        target = mirror.release(tag)
        for asset in mirror.attachments(target):
            if asset['name'] == name:
                mirror.gc('/releases/' + tag + '/attach_files/' + str(int(asset['id'])), method='DELETE')
        source = self.asset(tag, name)
        if source:
            mirror.gh('/releases/assets/' + str(int(source['id'])), method='DELETE')
        if self.asset(tag, name) or any(a['name'] == name for a in mirror.attachments(mirror.release(tag))):
            raise ValueError('Asset remains after removal: ' + tag + '/' + name)

    def put_catalog(self, catalog, append_missing=False):
        tag = catalog['tag']
        previous = self.catalog(tag)
        if previous is not None and previous != catalog:
            additions = set(catalog['assets']) - set(previous['assets'])
            unchanged = ({k: v for k, v in previous.items() if k != 'assets'} ==
                         {k: v for k, v in catalog.items() if k != 'assets'} and
                         all(catalog['assets'].get(k) == v for k, v in previous['assets'].items()))
            if not (append_missing and unchanged and additions and
                    additions <= {'Runtime_x64.zip', 'Runtime_x86.zip'} and
                    all(catalog['assets'][k]['scope'] == 'Patch' and catalog['assets'][k]['name'] == k
                        for k in additions)):
                raise ValueError('Refusing to rewrite version catalog: ' + tag)
        path = self.directory / (tag + '-resources.json')
        if previous == catalog:
            path = self.download(tag, self.asset(tag, CATALOG))
        else:
            path.write_text(json.dumps(catalog, ensure_ascii=True, indent=2) + '\n', encoding='utf-8')
        self.put(tag, CATALOG, path, replace=append_missing)

    def shared_indexes(self):
        for scope in ('Common', 'Patch'):
            entries = {a['name']: self.describe(scope, a) for a in self.assets(scope)
                       if a['name'] not in (CATALOG, LEGACY_INDEX)
                       and not re.search(r'\.(?:parts\.json|part\d{4})$', a['name'])}
            catalog = dict(schema=1, tag=scope, assets=entries)
            path = self.directory / (scope + '-resources.json')
            path.write_text(json.dumps(catalog, ensure_ascii=True, indent=2) + '\n', encoding='utf-8')
            self.put(scope, CATALOG, path, replace=True)


def catalogs(store):
    result = {}
    for release in store.releases():
        tag = release['tag_name']
        if managed_tag(tag):
            value = store.catalog(tag)
            if value:
                result[tag] = value
    return result


def preserve_dependents(store, known, scope, name, old):
    """No shared mutation until *every* dependent version is verified on both sites."""
    expected = record(old, scope, name)
    dependents = [(tag, logical, entry) for tag, catalog in known.items()
                  for logical, entry in catalog['assets'].items()
                  if entry['scope'] == scope and entry['name'] == name]
    for tag, logical, entry in dependents:
        override = store.asset(tag, logical)
        if override:
            # Resume a partially uploaded archive without changing its bytes.
            if override.get('digest') != 'sha256:' + entry['sha256'] or override['size'] != entry['size']:
                raise ValueError('Historical override checksum differs: ' + tag + '/' + logical)
            store.put(tag, logical, store.download(tag, override))
            store.verify(tag, logical, entry)
        elif entry['sha256'] == expected['sha256'] and entry['size'] == expected['size']:
            path = store.download(scope, old)
            store.put(tag, logical, path)
            store.verify(tag, logical, entry)
        else:
            raise ValueError('Unarchived historical dependency: ' + tag + '/' + logical)


def publish_shared(store, known, scope, name, path):
    old = store.asset(scope, name)
    if old:
        previous = store.download(scope, old)
        if fingerprint(previous) == fingerprint(path):
            store.put(scope, name, previous)
            entry = record(old, scope, name)
            entry['purpose'] = purpose(name)
            if name.endswith(('.zip', '.tar.bz2', '.tar.gz', '.tgz')):
                entry['files'] = archive_files(previous)
            return entry
        preserve_dependents(store, known, scope, name, old)
    entry = store.put(scope, name, path, replace=bool(old))
    return dict(scope=scope, name=name, **entry)


def stage_category_retirements(store, known, logical, alias, destination):
    candidates = {(entry['scope'], entry['name']) for catalog in known.values()
                  for key, entry in catalog['assets'].items()
                  if key == logical and entry['scope'] in ('Common', 'Patch')
                  and entry['scope'] != destination and entry['name'] in (logical, alias)}
    result = []
    for scope, name in sorted(candidates):
        asset = store.asset(scope, name)
        if asset:
            preserve_dependents(store, known, scope, name, asset)
            result.append((scope, name, asset['digest']))
    return result


def finish_category_retirements(store, plans):
    seen = {}
    for scope, name, digest in plans:
        if (scope, name) in seen and seen[(scope, name)] != digest:
            raise ValueError('Resource changed during category relocation')
        seen[(scope, name)] = digest
    for (scope, name), digest in seen.items():
        current = store.asset(scope, name)
        if current:
            if current['digest'] != digest:
                raise ValueError('Refusing to remove a changed shared resource')
            store.delete(scope, name)


def common_entries(store):
    entries = {}
    for scope in ('Common', 'Patch'):
        for asset in store.assets(scope):
            name = asset['name']
            if name in (CATALOG, LEGACY_INDEX) or re.search(r'\.(?:parts\.json|part\d{4})$', name):
                continue
            # Architecture-specific plugin packages belong to their matching catalog only.
            logical = re.sub(r'_(x64|x86)(\.zip)$', r'\2', name)
            if logical in bundle_names():
                continue
            expected_scope = ('Patch' if name in POLICY['patch'] else
                              'Common' if name in POLICY.get('common', []) else None)
            if expected_scope and scope != expected_scope:
                continue
            entries[name] = store.describe(scope, asset)
    required_globals = set(POLICY.get('common', [])) | (set(POLICY['patch']) - set(bundle_names()))
    if not required_globals <= set(entries):
        raise ValueError('Global resources absent from their configured category: ' +
                         ', '.join(sorted(required_globals - set(entries))))
    return entries


def frozen_globals(store, tag, sibling_tag, sibling):
    """Resume a half-published architecture pair using its original dependency set."""
    entries = {}
    for logical, pinned in sibling['assets'].items():
        if logical in sibling['build_assets']:
            continue
        entry = dict(pinned)
        shared = store.asset(entry['scope'], entry['name'])
        if entry['scope'] in ('Common', 'Patch') and shared and shared.get('digest') == 'sha256:' + entry['sha256'] and shared['size'] == entry['size']:
            store.verify(entry['scope'], entry['name'], entry)
        else:
            archived = store.asset(sibling_tag, logical)
            if not archived or archived.get('digest') != 'sha256:' + entry['sha256'] or archived['size'] != entry['size']:
                raise ValueError('Original release-family dependency is absent: ' + logical)
            store.put(tag, logical, store.download(sibling_tag, archived))
        if entry['scope'] == sibling_tag:
            entry['scope'] = tag
            entry['name'] = logical
        entries[logical] = entry
    return entries


def migrate(store):
    """Initial migration: legacy 1.2 tags are outside the managed namespace."""
    print('Inventory managed releases and capture current hashes', flush=True)
    known = catalogs(store)
    version_releases = [r['tag_name'] for r in store.releases() if managed_tag(r['tag_name'])]
    # Capture all original metadata before the first write.
    originals = {tag: store.assets(tag) for tag in version_releases}
    common = store.assets('Common')
    patch_sources = sorted((a for a in common if a['name'] in POLICY['patch']), key=lambda a: a['size'])
    store.ensure('Patch')
    plan = []
    stopped = threading.Event()
    def stage_patch(asset):
        if stopped.is_set():
            return
        try:
            store.put('Patch', asset['name'], store.download('Common', asset))
        except Exception:
            stopped.set()
            raise
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(stage_patch, asset) for asset in patch_sources]
        try:
            for future in futures:
                future.result()
        except Exception:
            for future in futures:
                future.cancel()
            raise
    plan.extend(('Common', asset['name'], 'Patch', asset['name']) for asset in patch_sources)
    # Oldest first. In case legacy tags contain multiple generations, keep the newest
    # in Common and preserve previous generations under their original version tags.
    pending = {}
    for tag in sorted(version_releases, key=version_key):
        if tag in known:
            pending[tag] = known[tag]
            for logical, entry in known[tag]['assets'].items():
                if entry['scope'] == 'Common' and logical in POLICY['shared']:
                    plan.append((tag, logical, 'Common', entry['name']))
            continue
        arch = VERSION_TAG.fullmatch(tag)[3]
        entries = common_entries(store)
        for asset in originals[tag]:
            name = asset['name']
            if name in (CATALOG, LEGACY_INDEX) or re.search(r'\.(?:parts\.json|part\d{4})$', name):
                continue
            if name not in POLICY['versioned'] + POLICY['shared'] + POLICY['patch']:
                raise ValueError('Unclassified version asset: ' + tag + '/' + name)
            if name in POLICY['shared']:
                destination = shared_name(name, arch)
                entries[name] = publish_shared(store, {**known, **pending}, 'Common', destination,
                                               store.download(tag, asset))
                plan.append((tag, name, 'Common', destination))
            else:
                entries[name] = store.describe(tag, asset)
                store.verify(tag, name, entries[name])
        pending[tag] = dict(schema=1, tag=tag, assets=entries,
                            build_assets=sorted(a['name'] for a in originals[tag] if a['name'] not in (CATALOG, LEGACY_INDEX)))
    # Commit catalogs only after every destination has been verified.
    for catalog in pending.values():
        store.put_catalog(catalog)
    for source_tag, name, destination, renamed in plan:
        expected = store.asset(source_tag, name)
        if not expected:
            continue
        # Keep a version snapshot if the shared destination holds a newer generation.
        target = store.asset(destination, renamed)
        if target and target['digest'] == expected['digest']:
            store.verify(destination, renamed, record(expected, destination, renamed))
            store.delete(source_tag, name)
    store.shared_indexes()
    return dict(status='passed', catalogs=sorted(pending), migrated=plan, patch='Patch')


def validate_universal_builds(directory):
    # Validate both architectures before the first upload or shared replacement.
    for name in POLICY.get('universal', []):
        paths = [directory / ('RMTAssets_' + arch) / name for arch in ('x64', 'x86')]
        if any(p.exists() for p in paths) and (not all(p.exists() for p in paths)
                or fingerprint(paths[0]) != fingerprint(paths[1])):
            raise ValueError('Universal bundle differs across architectures: ' + name)


def publish(store, directory):
    info = json.loads((directory / 'release-info.json').read_text(encoding='utf-8-sig'))
    validate_universal_builds(directory)
    known = catalogs(store)
    new_tags = ['v' + info['asset_tag'] + '_' + arch for arch in ('x64', 'x86')]
    latest = max((version_key(tag) for tag in known), default=())
    if any(version_key(tag) < latest and tag not in known for tag in new_tags):
        raise ValueError('Stale release replay cannot change shared resources')
    store.ensure('Common')
    store.ensure('Patch')
    result = []
    pending = {}
    retirements = []
    for tag, arch in zip(new_tags, ('x64', 'x86')):
        source = directory / ('RMTAssets_' + arch)
        paths = sorted(source.glob('*.zip'))
        if not paths or not set(POLICY.get('required', POLICY['versioned'])) <= {p.name for p in paths}:
            raise ValueError('Incomplete build artifacts: ' + arch)
        sibling_tag = next((other for other in new_tags if other != tag and other in known), None)
        resuming_family = tag not in known and sibling_tag is not None
        entries = (frozen_globals(store, tag, sibling_tag, known[sibling_tag])
                   if resuming_family else common_entries(store))
        for path in paths:
            name = path.name
            if name not in bundle_names():
                raise ValueError('Unclassified build artifact: ' + name)
            destination = (tag if name in POLICY['versioned'] else
                           'Patch' if name in POLICY['patch'] else 'Common')
            if tag not in known:
                retirements.extend(stage_category_retirements(store, known, name,
                                                              shared_name(name, arch), destination))
            if tag in known:
                pinned = known[tag]['assets'].get(name)
                if not pinned:
                    raise ValueError('Released catalog does not contain ' + name)
                stored = store.asset(tag, name) or store.asset(pinned['scope'], pinned['name'])
                if not stored:
                    raise ValueError('Pinned resource is absent')
                stored_tag = tag if store.asset(tag, name) else pinned['scope']
                if fingerprint(store.download(stored_tag, stored)) != fingerprint(path):
                    raise ValueError('Published resource cannot be changed: ' + tag + '/' + name)
                store.verify(stored_tag, stored['name'], pinned)
                entries[name] = pinned
            elif name not in POLICY['versioned']:
                scope = 'Patch' if name in POLICY['patch'] else 'Common'
                alias = shared_name(name, arch)
                if resuming_family:
                    current = store.asset(scope, alias)
                    if current and fingerprint(store.download(scope, current)) == fingerprint(path):
                        # Repair the other provider if needed, without changing generation.
                        entry = store.put(scope, alias, store.download(scope, current))
                    else:
                        # A newer shared generation may have appeared since the failure.
                        # Preserve this build as a version override instead of rolling it back.
                        entry = store.put(tag, name, path)
                    entries[name] = dict(scope=scope, name=alias, **entry)
                else:
                    entries[name] = publish_shared(store, known, scope, alias, path)
            else:
                old = store.asset(tag, name) if any(r['tag_name'] == tag for r in store.releases()) else None
                if old and fingerprint(store.download(tag, old)) == fingerprint(path):
                    path = store.download(tag, old)
                entry = store.put(tag, name, path)
                entries[name] = dict(scope=tag, name=name, **entry)
        if tag in known:
            # Never refresh a historical catalog's Common/Patch dependencies on replay.
            catalog = known[tag]
            if {path.name for path in paths} != set(catalog['build_assets']):
                raise ValueError('Published build asset set changed')
        else:
            catalog = dict(schema=1, tag=tag, assets=entries, build_assets=sorted(path.name for path in paths))
        pending[tag] = catalog
        result.append(tag)
    for catalog in pending.values():
        store.put_catalog(catalog)
    finish_category_retirements(store, retirements)
    store.shared_indexes()
    return dict(status='passed', catalogs=result, asset_tags=result + ['Common', 'Patch'])


def update_shared(store, known, scope, directory):
    """Explicit Common/Patch maintenance; old version catalogs never change."""
    if scope not in ('Common', 'Patch'):
        raise ValueError('Invalid shared scope')
    result = []
    retirements = []
    for path in sorted(directory.iterdir()):
        if not path.is_file():
            continue
        name = mirror.safe_name(path.name)
        if name in (CATALOG, LEGACY_INDEX) or name.endswith('.parts.json'):
            raise ValueError('Descriptors and catalogs are not standalone shared resources')
        declared = POLICY['versioned'] + POLICY['shared'] + POLICY['patch'] + POLICY.get('common', [])
        logical = name if name in declared else re.sub(r'_(x64|x86)(\.zip)$', r'\2', name)
        if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9._-]*', name):
            raise ValueError('Unsupported resource filename')
        if logical not in POLICY['shared'] + POLICY['patch'] + POLICY.get('common', []):
            raise ValueError('Unclassified shared resource: ' + name)
        if (logical in POLICY['patch']) != (scope == 'Patch'):
            raise ValueError('Resource category mismatch: ' + name)
        retirements.extend(stage_category_retirements(store, known, logical, name, scope))
        result.append(publish_shared(store, known, scope, name, path))
    if not result:
        raise ValueError('No shared updates supplied')
    finish_category_retirements(store, retirements)
    store.shared_indexes()
    return dict(status='passed', updated=result)


def complete_catalogs(store):
    """Append initial offline-runtime omissions; existing pins may never change."""
    patch = store.catalog('Patch')
    if not patch:
        raise ValueError('Patch resource index is required')
    amended = []
    for tag, catalog in catalogs(store).items():
        missing = [name for name in ('Runtime_x64.zip', 'Runtime_x86.zip')
                   if name not in catalog['assets']]
        if not missing:
            continue
        for name in missing:
            entry = patch['assets'].get(name)
            if not entry or entry['scope'] != 'Patch' or entry['name'] != name:
                raise ValueError('Pinned offline runtime is absent from Patch')
            store.verify('Patch', name, entry)
            catalog['assets'][name] = entry
        store.put_catalog(catalog, append_missing=True)
        amended.append(dict(tag=tag, added=missing))
    return dict(status='passed', amended=amended)


def normalize_resources(store):
    """Consolidate universal bundles without rewriting any historical pin."""
    known = catalogs(store)
    changed = []
    forbidden = {'Audio.zip': {'playaudio.vbs'}, 'ViGEm.zip': {'xbox.png'}}
    for logical in POLICY.get('universal', []):
        names = [logical] + [os.path.splitext(logical)[0] + '_' + arch + '.zip'
                             for arch in ('x64', 'x86')]
        sources = [(name, store.asset('Common', name)) for name in names]
        sources = [(name, asset) for name, asset in sources if asset]
        if not sources:
            raise ValueError('Universal bundle is absent: ' + logical)
        # Compare the retained files, allowing an idempotent retry after the clean
        # universal target was uploaded but old aliases have not yet been removed.
        contents = []
        for name, asset in sources:
            with zipfile.ZipFile(store.download('Common', asset)) as archive:
                items = {item.filename: archive.read(item) for item in archive.infolist()
                         if not item.is_dir() and Path(item.filename).name.lower()
                         not in forbidden.get(logical, set())}
                if len(archive.namelist()) != len(set(archive.namelist())) or not items:
                    raise ValueError('Invalid universal bundle: ' + name)
                contents.append(items)
        if any(items != contents[0] for items in contents[1:]):
            raise ValueError('Architecture contents differ: ' + logical)
        # Every old dependency is secured on both providers before alias retirement.
        for name, asset in sources:
            preserve_dependents(store, known, 'Common', name, asset)
        target = store.directory / 'normalized' / logical
        target.parent.mkdir(exist_ok=True)
        with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for name, data in sorted(contents[0].items()):
                info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, data)
        publish_shared(store, known, 'Common', logical, target)
        for name, asset in sources:
            if name != logical:
                current = store.asset('Common', name)
                if current and current['digest'] != asset['digest']:
                    raise ValueError('Universal source changed during normalization')
                store.delete('Common', name)
        changed.append(logical)
    # Legacy tags receive an inventory too, but their runtime assets remain intact.
    for release in store.releases():
        tag = release['tag_name']
        if tag not in ('Common', 'Patch') and tag not in known:
            entries = {a['name']: store.describe(tag, a) for a in store.assets(tag)
                       if a['name'] not in (CATALOG, LEGACY_INDEX)}
            store.put_catalog(dict(schema=1, tag=tag, assets=entries))
    store.shared_indexes()
    for release in store.releases():
        tag = release['tag_name']
        # Store.delete also cleans a surviving GitCode copy after a partial failure.
        store.delete(tag, LEGACY_INDEX)
    from release_presentation import organize_releases
    presentation = organize_releases(store)
    return dict(status='passed', universal=changed, presentation=presentation)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=('migrate', 'publish', 'shared', 'shared-url', 'complete-catalogs', 'normalize', 'presentation'))
    parser.add_argument('--directory', type=Path)
    parser.add_argument('--scope', choices=('Common', 'Patch'))
    parser.add_argument('--url')
    parser.add_argument('--name')
    parser.add_argument('--sha256')
    args = parser.parse_args()
    report = Path(os.environ.get('RUNNER_TEMP', 'Test/output')) / 'resource-layout-result.json'
    try:
        with tempfile.TemporaryDirectory(dir=os.environ.get('RUNNER_TEMP')) as directory:
            store = Store(directory)
            if args.mode == 'migrate':
                result = migrate(store)
            elif args.mode == 'normalize':
                result = normalize_resources(store)
            elif args.mode == 'presentation':
                from release_presentation import organize_releases
                result = dict(status='passed', presentation=organize_releases(store))
            elif args.mode == 'complete-catalogs':
                result = complete_catalogs(store)
            elif args.mode == 'shared-url':
                address = urlsplit(args.url or '')
                if (address.scheme != 'https' or address.netloc != 'github.com'
                        or not re.fullmatch(r'/[^/]+/[^/]+/releases/download/[^/]+/[^/]+', address.path)
                        or address.query or address.fragment
                        or not re.fullmatch('[0-9a-f]{64}', args.sha256 or '')):
                    raise ValueError('A public GitHub release URL and SHA-256 are required')
                incoming = Path(directory) / 'incoming'
                incoming.mkdir()
                path = incoming / mirror.safe_name(args.name)
                with urlopen(Request(args.url, headers={'User-Agent': 'RMT-resource-layout'}), timeout=90) as response:
                    with path.open('wb') as output:
                        shutil.copyfileobj(response, output, 1024 * 1024)
                if mirror.sha(path) != 'sha256:' + args.sha256:
                    raise ValueError('Shared update source checksum mismatch')
                result = update_shared(store, catalogs(store), args.scope, incoming)
            elif not args.directory:
                raise ValueError('--directory is required')
            elif args.mode == 'publish':
                result = publish(store, args.directory)
            else:
                result = update_shared(store, catalogs(store), args.scope, args.directory)
            if args.mode not in ('normalize', 'presentation'):
                from release_presentation import refresh_descriptions
                refresh_descriptions(store)
    except Exception as exc:
        import traceback
        result = dict(status='failed', mode=args.mode, error=type(exc).__name__,
                      trace=[dict(function=frame.name, line=frame.lineno) for frame in traceback.extract_tb(exc.__traceback__)])
        if isinstance(exc, ValueError):
            result['detail'] = str(exc)
        if hasattr(exc, 'code'):
            result['http_status'] = exc.code
    report.write_text(json.dumps(result, ensure_ascii=True, indent=2), encoding='utf-8')
    print(json.dumps(result), flush=True)
    raise SystemExit(0 if result['status'] == 'passed' else 1)
