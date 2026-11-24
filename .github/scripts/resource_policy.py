"""Published stable tags are append-only, including resource inventories."""
import json
import re


def mutable_tag(tag):
    # Unknown tag formats are protected. Only the established F preview syntax
    # explicitly identifies a test release; release flags cannot unlock a stable tag.
    return tag in ('Common', 'Patch') or bool(re.fullmatch(
        r'(?:RMT)?v\d+(?:\.\d+)+F\d+(?:_(?:x64|x86))?', tag))


def catalog_additions(before, after):
    old, new = json.loads(before), json.loads(after)
    return (isinstance(old.get('assets'), dict) and isinstance(new.get('assets'), dict)
            and {k: v for k, v in old.items() if k != 'assets'} ==
                {k: v for k, v in new.items() if k != 'assets'}
            and all(new['assets'].get(k) == v for k, v in old['assets'].items()))
