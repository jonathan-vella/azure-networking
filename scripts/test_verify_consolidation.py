import json
from pathlib import Path
import tempfile
import unittest

from verify_consolidation import check_links, check_manifest, check_workflows


class ConsolidationChecksTests(unittest.TestCase):
    def test_links_validate_assets_and_anchors(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "README.md").write_text("[Next](docs/next.md#destination)\n![Image](docs/diagram.svg)")
            (root / "docs").mkdir()
            (root / "docs" / "next.md").write_text("# Destination\n")
            (root / "docs" / "diagram.svg").write_text("<svg/>")
            self.assertEqual(check_links(root), [])
            (root / "README.md").write_text("[Next](docs/next.md#missing)\n![Image](docs/missing.svg)")
            self.assertEqual(len(check_links(root)), 2)

    def test_checks_case_even_on_windows(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "README.md").write_text("[Next](docs/next.md)")
            (root / "docs").mkdir()
            (root / "docs" / "Next.md").write_text("# Next\n")
            self.assertEqual(len(check_links(root)), 1)

    def test_angular_templates_resolve_runtime_assets_with_exact_case(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            app = root / "tools" / "app"
            template = app / "src" / "app" / "page.html"
            template.parent.mkdir(parents=True)
            (app / "angular.json").write_text(json.dumps({"projects": {"app": {"sourceRoot": "src"}}}))
            assets = app / "src" / "assets"
            assets.mkdir()
            (assets / "Logo.svg").write_text("<svg/>")
            (app / ".angular").mkdir()
            (app / ".angular" / "generated.html").write_text('<img src="absent.svg">')
            template.write_text('<base href="/"><img src="assets/Logo.svg">')
            self.assertEqual(check_links(root), [])
            template.write_text('<img src="assets/logo.svg">')
            self.assertEqual(len(check_links(root)), 1)

    def test_links_reject_root_relative_paths_and_traversal(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "README.md").write_text("[Root](/images/a.svg)\n[Outside](../outside.md)")
            self.assertEqual(len(check_links(root)), 2)

    def test_links_in_code_examples_are_not_navigation(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "README.md").write_text(
                '```html\n<img src="absent.svg">\n```\n\n`[Example](absent.md)`\n')
            self.assertEqual(check_links(root), [])

    def test_manifest_reports_blocked_sources_without_requiring_copied_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = {"sources": [{"repository": "example/blocked", "status": "blocked-license",
                                 "file_count": 1, "files": [{"source": "README.md"}]}]}
            (root / "sources.json").write_text(json.dumps(data))
            errors, blocked = check_manifest(root)
            self.assertEqual(errors, [])
            self.assertEqual(blocked, ["example/blocked"])

    def test_manifest_rejects_missing_prepared_file(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = {"sources": [{"repository": "example/ready", "status": "prepared-local",
                                 "file_count": 1, "files": [{
                                     "disposition": "imported", "destination": "absent.md"}]}]}
            (root / "sources.json").write_text(json.dumps(data))
            errors, blocked = check_manifest(root)
            self.assertEqual(len(errors), 1)
            self.assertEqual(blocked, [])

    def test_manifest_rejects_accidentally_copied_withheld_material(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "withheld.md").write_text("Not cleared for publication")
            data = {"sources": [{"repository": "example/blocked", "status": "blocked-clearance",
                                 "file_count": 1, "files": [{"destination": "withheld.md"}]}]}
            (root / "sources.json").write_text(json.dumps(data))
            errors, blocked = check_manifest(root)
            self.assertIn("withheld destination is present", errors[0])
            self.assertEqual(blocked, ["example/blocked"])

    def test_publication_block_does_not_skip_prepared_file_validation(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = {"sources": [{"repository": "example/sanitized", "status": "prepared-local",
                                 "publication_blocks": ["credential-revocation-unconfirmed"],
                                 "file_count": 1, "files": [{
                                     "disposition": "imported", "destination": "absent.md"}]}]}
            (root / "sources.json").write_text(json.dumps(data))
            errors, blocked = check_manifest(root)
            self.assertEqual(len(errors), 1)
            self.assertEqual(blocked, ["example/sanitized"])

    def test_manifest_rejects_destination_traversal(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = {"sources": [{"repository": "example/ready", "status": "prepared-local",
                                 "file_count": 1, "files": [{
                                     "disposition": "imported", "destination": "../outside.md"}]}]}
            (root / "sources.json").write_text(json.dumps(data))
            errors, _ = check_manifest(root)
            self.assertIn("destination escapes", errors[0])

    def test_workflows_reject_unreviewed_deployment(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            workflows = root / ".github" / "workflows"
            workflows.mkdir(parents=True)
            (workflows / "deploy.yml").write_text("on: push\njobs: {}\n")
            self.assertTrue(check_workflows(root))


if __name__ == "__main__":
    unittest.main()
