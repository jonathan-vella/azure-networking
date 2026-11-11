"""Verify prepared source coverage and case-sensitive local documentation links."""

import argparse
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import sys
from urllib.parse import unquote, urlsplit

import markdown
import yaml

ROOT = Path(__file__).resolve().parents[1]


class References(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.ids = set()

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if attrs.get("id"):
            self.ids.add(attrs["id"])
        if tag == "a" and attrs.get("name"):
            self.ids.add(attrs["name"])
        for attr in ("href", "src"):
            if attrs.get(attr):
                self.links.append(attrs[attr])


def exact_path(path):
    """Check spelling even on case-insensitive Windows filesystems."""
    if not path.exists():
        return False
    for parent in path.parents:
        child = path.relative_to(parent).parts[0]
        if child not in {p.name for p in parent.iterdir()}:
            return False
    return True


def document(path):
    text = path.read_text(encoding="utf-8-sig")
    parser = References()
    if path.suffix.lower() == ".md":
        text = markdown.markdown(text, extensions=[
            "toc", "tables", "attr_list", "md_in_html", "pymdownx.superfences", "footnotes", "def_list",
        ])
    parser.feed(text)
    return parser


def check_links(root):
    root = root.resolve()
    errors = []
    documents = {}
    angular_sources = []
    candidates = list(root.glob("*.md"))
    for folder in ("docs", "labs", "tools"):
        for directory, children, files in os.walk(root / folder):
            children[:] = [name for name in children
                           if name not in ("node_modules", ".terraform", ".git", ".angular", "dist", "bin", "obj")]
            if "angular.json" in files:
                config = json.loads((Path(directory) / "angular.json").read_text(encoding="utf-8"))
                angular_sources.extend((Path(directory) / project["sourceRoot"]).resolve()
                                       for project in config["projects"].values() if project.get("sourceRoot"))
            candidates += [Path(directory) / name for name in files
                           if Path(name).suffix.lower() in (".md", ".html")]
    for path in candidates:
        documents[path.resolve()] = document(path)
    for path, refs in list(documents.items()):
        angular_source = next((source for source in angular_sources
                               if path.suffix.lower() == ".html" and path.is_relative_to(source)), None)
        for link in refs.links:
            url = urlsplit(link)
            if url.scheme or url.netloc:
                continue
            # Angular's base href refers to its deployed application root.
            if angular_source and url.path == "/":
                continue
            if link.startswith("/"):
                errors.append(f"{path.relative_to(root)}: non-portable root-relative link: {link}")
                continue
            target = Path(os.path.abspath(path.parent / unquote(url.path))) if url.path else path
            if angular_source and unquote(url.path).startswith("assets/"):
                target = angular_source / unquote(url.path)
            if not target.resolve().is_relative_to(root):
                errors.append(f"{path.relative_to(root)}: link escapes repository: {link}")
                continue
            if not exact_path(target):
                errors.append(f"{path.relative_to(root)}: missing or incorrectly cased target: {link}")
                continue
            if url.fragment and target.suffix.lower() in (".md", ".html"):
                target_refs = documents.get(target)
                if target_refs is None:
                    target_refs = document(target)
                    documents[target] = target_refs
                if unquote(url.fragment) not in target_refs.ids:
                    errors.append(f"{path.relative_to(root)}: missing anchor: {link}")
    return errors


def check_manifest(root):
    root = root.resolve()
    manifest = json.loads((root / "sources.json").read_text(encoding="utf-8"))
    errors = []
    blocked = []
    for source in manifest["sources"]:
        if source["file_count"] != len(source["files"]):
            errors.append(f"{source['repository']}: incomplete file mapping")
        if source["status"].startswith("blocked"):
            blocked.append(source["repository"])
            for entry in source["files"]:
                destination = entry.get("destination")
                if destination and (root / destination).exists():
                    errors.append(f"{source['repository']}: withheld destination is present: {destination}")
            continue
        if source.get("publication_blocks"):
            blocked.append(source["repository"])
        for entry in source["files"]:
            disposition = entry["disposition"]
            if disposition == "excluded-generated-macos-metadata":
                continue
            if disposition not in ("imported", "reference-only", "deduplicated-symlink-alias",
                                   "deduplicated-directory-alias"):
                errors.append(f"{source['repository']}: unknown disposition {disposition}")
                continue
            target = root / entry["destination"]
            if not target.resolve().is_relative_to(root):
                errors.append(f"{source['repository']}: destination escapes repository")
                continue
            if disposition == "deduplicated-directory-alias":
                if not target.is_dir() or target.is_symlink() or not exact_path(target):
                    errors.append(f"{source['repository']}: invalid directory alias {entry['destination']}")
                continue
            if not target.is_file() or target.is_symlink() or not exact_path(target):
                errors.append(f"{source['repository']}: absent or non-portable destination {entry['destination']}")
                continue
            expected = entry.get("prepared_sha256")
            if not expected and disposition in ("imported", "reference-only"):
                errors.append(f"{entry['destination']}: missing prepared digest")
            if expected and hashlib.sha256(target.read_bytes()).hexdigest() != expected:
                errors.append(f"{entry['destination']}: prepared content differs from manifest")
    if (root / "migration-staging").exists():
        errors.append("Private staging must not be in the destination")
    return errors, blocked


def check_workflows(root):
    """Only the reviewed, read-only check workflow may be active."""
    expected = {
        "name": "Consolidation checks",
        "on": {"push": {"branches": ["main"]}, "pull_request": "", "workflow_dispatch": ""},
        "permissions": {"contents": "read"},
        "jobs": {"documentation": {
            "runs-on": "ubuntu-latest",
            "steps": [
                {"uses": "actions/checkout@v6"},
                {"uses": "actions/setup-python@v6", "with": {"python-version": "3.12", "cache": "pip"}},
                {"uses": "actions/setup-node@v6", "with": {"node-version": "22"}},
                {"run": "python -m pip install -r requirements.txt"},
                {"run": 'python -m unittest discover -s scripts -p "test_*.py"'},
                {"run": "python scripts/verify_consolidation.py"},
                {"run": "node scripts/verify.mjs"},
                {"run": "python -m mkdocs build --strict"},
            ],
        }, "playground": {
            "runs-on": "ubuntu-latest",
            "steps": [
                {"uses": "actions/checkout@v6"},
                {"run": "az bicep install --version v0.48.1"},
                {"run": 'az bicep build --file labs/virtual-wan-playground/main.bicep --outfile "$RUNNER_TEMP/playground.json"'},
            ],
        }},
    }
    errors = []
    folder = root / ".github" / "workflows"
    workflows = list(folder.glob("*.yml")) + list(folder.glob("*.yaml"))
    if {p.name for p in workflows} != {"checks.yml"}:
        errors.append("Active workflows differ from the approved checks.yml allowlist")
    for workflow in workflows:
        # BaseLoader retains the YAML key 'on' rather than interpreting it as a boolean.
        actual = yaml.load(workflow.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
        if workflow.name != "checks.yml" or actual != expected:
            errors.append(f"{workflow.name}: workflow differs from reviewed non-deploying checks")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()
    errors, blocked = check_manifest(ROOT)
    errors += check_links(ROOT)
    errors += check_workflows(ROOT)
    if blocked:
        print("Blocked sources: " + ", ".join(blocked))
        if args.require_complete:
            errors.append("Full consolidation is blocked")
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print("Prepared file coverage and case-sensitive documentation links verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
