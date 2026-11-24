"""Explicit, bounded cleanup of the three user-retired historical resources."""
import copy
import json
from pathlib import PurePosixPath
import zipfile

import sync_gitcode_assets as mirror

RETIRED = {'playaudio.vbs', 'xbox.png', 'countdown.exe'}


def retired(name):
    return PurePosixPath(name.replace('\\', '/')).name.casefold() in RETIRED


def clean_zip(source, destination):
    removed = []
    with zipfile.ZipFile(source) as before, zipfile.ZipFile(
            destination, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as after:
        if len(before.namelist()) != len(set(before.namelist())):
            raise ValueError('Duplicate ZIP entries')
        for item in before.infolist():
            if retired(item.filename):
                removed.append(item.filename)
            else:
                after.writestr(item, before.read(item))
    with zipfile.ZipFile(source) as before, zipfile.ZipFile(destination) as after:
        expected = {i.filename for i in before.infolist() if not retired(i.filename)}
        if set(after.namelist()) != expected or any(before.read(n) != after.read(n) for n in expected):
            raise ValueError('Cleanup changed a retained ZIP entry')
        if not any(not i.is_dir() for i in after.infolist()):
            raise ValueError('Cleanup would leave an empty ZIP')
    return removed


def retire_resources(store, catalog_name):
    releases = store.releases()
    catalogs = {r['tag_name']: store.catalog(r['tag_name']) for r in releases}
    if any(c is None for c in catalogs.values()):
        raise ValueError('Every release needs a resource catalog before cleanup')
    snapshots = copy.deepcopy(catalogs)
    direct, archives = [], []
    for release in releases:
        tag = release['tag_name']
        for asset in store.assets(tag):
            name = asset['name']
            if retired(name):
                direct.append((tag, name))
            elif name.lower().endswith('.zip'):
                entry = catalogs[tag]['assets'].get(name)
                pending = catalogs[tag].get('retirement_plan', {}).get(name)
                if pending and asset.get('digest') == 'sha256:' + pending['sha256']:
                    original = store.download(tag, asset)
                    if original.stat().st_size != pending['size']:
                        raise ValueError('Pending cleanup size mismatch')
                    archives.append(dict(tag=tag, name=name, path=original,
                                         removed=pending['removed'], before=asset, planned=pending))
                    continue
                # A matching SHA binds the recorded archive directory to these bytes.
                if (entry and entry.get('sha256') == asset.get('digest', '')[7:]
                        and entry.get('files') and not any(retired(f['name']) for f in entry['files'])):
                    continue
                original = store.download(tag, asset)
                with zipfile.ZipFile(original) as archive:
                    if not any(retired(n) for n in archive.namelist()):
                        continue
                directory = store.directory / 'retired-cleanup' / tag
                directory.mkdir(parents=True, exist_ok=True)
                cleaned = directory / name
                removed = clean_zip(original, cleaned)
                planned = dict(sha256=mirror.sha(cleaned)[7:], size=cleaned.stat().st_size,
                               removed=removed)
                if pending and planned != pending:
                    raise ValueError('Retry produced different cleanup bytes')
                archives.append(dict(tag=tag, name=name, path=cleaned,
                                     removed=removed, before=asset, planned=planned))
    # All replacement ZIPs are complete and retained contents are compared first.
    # Persist the replacement hashes before overwriting ZIPs, so an interrupted
    # upload can repair the other provider and finish the matching catalog later.
    for item in archives:
        catalogs[item['tag']].setdefault('retirement_plan', {})[item['name']] = item['planned']
    for tag, catalog in catalogs.items():
        if catalog.get('retirement_plan'):
            path = store.directory / (tag + '-retirement-plan.json')
            path.write_text(json.dumps(catalog, ensure_ascii=True, indent=2) + '\n', encoding='utf-8')
            store.put(tag, catalog_name, path, replace=True)
    replacements = {}
    for item in archives:
        current = store.asset(item['tag'], item['name'])
        if current.get('digest') != item['before']['digest']:
            raise ValueError('Archive changed during cleanup')
        entry = store.put(item['tag'], item['name'], item['path'], replace=True)
        replacements[(item['tag'], item['name'])] = entry
    changed = []
    for tag, catalog in catalogs.items():
        for logical, entry in list(catalog['assets'].items()):
            if retired(logical) or retired(entry['name']):
                del catalog['assets'][logical]
                continue
            # Version overrides take precedence over the original shared location.
            replacement = replacements.get((tag, logical))
            if replacement:
                catalog['assets'][logical] = dict(entry, **replacement, scope=tag, name=logical)
        if 'build_assets' in catalog:
            catalog['build_assets'] = [n for n in catalog['build_assets'] if not retired(n)]
        catalog.pop('retirement_plan', None)
        if catalog != snapshots[tag]:
            # This maintenance operation bypasses ordinary immutability only for
            # the exact removals and byte-verified ZIP replacements planned above.
            path = store.directory / (tag + '-retired-catalog.json')
            path.write_text(json.dumps(catalog, ensure_ascii=True, indent=2) + '\n', encoding='utf-8')
            store.put(tag, catalog_name, path, replace=True)
            changed.append(tag)
    for tag, name in direct:
        store.delete(tag, name)
    for release in releases:
        tag = release['tag_name']
        if any(retired(a['name']) for a in store.assets(tag)):
            raise ValueError('Retired attachment remains: ' + tag)
        catalog = store.catalog(tag)
        for logical, entry in catalog['assets'].items():
            if retired(logical) or any(retired(f['name']) for f in entry.get('files', [])):
                raise ValueError('Retired resource remains in the catalog: ' + tag + '/' + logical)
    return dict(status='passed', removed_attachments=direct,
                cleaned_archives=[{k: v for k, v in a.items() if k in ('tag', 'name', 'removed')}
                                  for a in archives], updated_catalogs=changed)
