"""Show "Nextshot" wherever the app's string catalogs show "Capso".

Fork-only. Swift sources keep upstream's keys ("Quit Capso"). This script
edits the catalogs instead: every locale's text, plus an explicit English
text for keys that name Capso. Run it again after each upstream sync; it
changes nothing on a second run.

Only "Capso" with a capital C changes, so IDs such as
com.awesomemacapps.capso stay. The script writes Xcode's own JSON layout and
stops if a load-and-save round trip would change a file.

Usage: python3 scripts/brand/rename-capso-strings.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOGS = [ROOT / "App/Resources/Localizable.xcstrings", ROOT / "App/Resources/InfoPlist.xcstrings"]
OLD, NEW = "Capso", "Nextshot"


def xcode_json(value, indent=0):
    """Serialize as Xcode writes .xcstrings: 2-space indent, " : ", empty objects on two lines."""
    pad = "  " * indent
    inner = "  " * (indent + 1)
    if isinstance(value, dict):
        if not value:
            return "{\n\n" + pad + "}"
        items = [inner + json.dumps(k, ensure_ascii=False) + " : " + xcode_json(v, indent + 1) for k, v in value.items()]
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(value, list):
        if not value:
            return "[\n\n" + pad + "]"
        items = [inner + xcode_json(v, indent + 1) for v in value]
        return "[\n" + ",\n".join(items) + "\n" + pad + "]"
    return json.dumps(value, ensure_ascii=False)


def rename_values(node):
    """Replace OLD with NEW in every "value" string under node. Returns the count."""
    count = 0
    if isinstance(node, dict):
        for key, child in node.items():
            if key == "value" and isinstance(child, str) and OLD in child:
                node[key] = child.replace(OLD, NEW)
                count += 1
            else:
                count += rename_values(child)
    elif isinstance(node, list):
        for child in node:
            count += rename_values(child)
    return count


def process(path):
    text = path.read_text(encoding="utf-8")
    data = json.loads(text)
    if xcode_json(data) != text:
        sys.exit(f"{path}: a round trip would change the file layout; stopping")
    source = data.get("sourceLanguage", "en")
    values = added = 0
    for key, entry in data["strings"].items():
        values += rename_values(entry)
        if OLD in key and entry.get("shouldTranslate", True) is not False:
            localizations = entry.setdefault("localizations", {})
            if source not in localizations:
                localizations[source] = {"stringUnit": {"state": "translated", "value": key.replace(OLD, NEW)}}
                entry["localizations"] = dict(sorted(localizations.items()))
                added += 1
    path.write_text(xcode_json(data), encoding="utf-8")
    print(f"{path.relative_to(ROOT)}: {values} texts renamed, {added} English texts added")


if __name__ == "__main__":
    for catalog in CATALOGS:
        process(catalog)
