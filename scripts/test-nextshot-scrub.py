#!/usr/bin/env python3
"""Guard for scripts/nextshot-scrub.py and the .noindex build folders."""

import pathlib
import plistlib
import sys
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
import importlib.util

spec = importlib.util.spec_from_file_location("scrub", SCRIPTS / "nextshot-scrub.py")
scrub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scrub)


def make_app(folder, name, identifier, version, build="1"):
    app = folder / name
    (app / "Contents").mkdir(parents=True)
    with (app / "Contents/Info.plist").open("wb") as stream:
        plistlib.dump({"CFBundleIdentifier": identifier,
                       "CFBundleShortVersionString": version,
                       "CFBundleVersion": build}, stream)
    return app


class ScrubTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name).resolve()
        self.keep = make_app(self.root / "Applications", "Nextshot Dev.app", scrub.DEV_ID, "0.8.0-dev", "934")
        self.legacy = make_app(self.root / "home/Applications", "Nextshot Dev.app", scrub.DEV_ID, "0.8.0-dev", "932")
        self.build = self.root / "wt/build"
        self.old = make_app(self.build / "local/Products/Debug", "Nextshot Dev.app", scrub.DEV_ID, "0.2.0-dev")
        self.prod = make_app(self.build / "release/export", "Nextshot.app", scrub.PRODUCTION_ID, "2026.10.25")
        self.fresh = make_app(self.build / "local.noindex/Products/Release", "Nextshot Dev.app",
                              scrub.DEV_ID, "0.8.0-dev", "934")
        self.volume = make_app(self.root / "Volumes/Nextshot", "Nextshot.app", scrub.PRODUCTION_ID, "0.8.0")
        make_app(self.root / "wt/build/other", "Other.app", "com.example.other", "1.0")

    def tearDown(self):
        self.tmp.cleanup()

    def entries(self, running=()):
        roots = [self.root / "Applications", self.root / "home/Applications", self.build,
                 self.root / "Volumes"]
        return {str(a.path): s for a, s in scrub.plan(roots, self.keep, [self.build], set(running))}

    def test_decisions(self):
        got = self.entries()
        self.assertEqual(got[str(self.keep)], "keep")
        self.assertEqual(got[str(self.old)], "remove")
        self.assertEqual(got[str(self.prod)], "remove")
        self.assertEqual(got[str(self.fresh)], "hidden")
        self.assertEqual(got[str(self.volume)], "manual")
        self.assertEqual(got[str(self.legacy)], "manual", "an old ~/Applications Dev copy is stale")
        self.assertEqual(len(got), 6, "a bundle with another ID must not be listed")

    def test_keep_path_is_applications(self):
        self.assertEqual(str(scrub.KEEP), "/Applications/Nextshot Dev.app")

    def test_two_paths_to_one_app_give_one_entry(self):
        alias = self.root / "alias"
        alias.symlink_to(self.root)
        roots = [self.build]
        extra = [alias / "wt/build/local/Products/Debug/Nextshot Dev.app"]
        apps = scrub.discover(roots, extra)
        self.assertEqual(sum(1 for a in apps if a.version == "0.2.0-dev"), 1)

    def test_archive_copy_is_kept(self):
        app = make_app(self.build / "release/Nextshot.xcarchive/Products/Applications", "Nextshot.app",
                       scrub.PRODUCTION_ID, "0.8.0")
        self.assertEqual(self.entries()[str(app)], "hidden")

    def test_running_copy_is_not_removed(self):
        self.assertEqual(self.entries(running=[self.old])[str(self.old)], "running")

    def test_remove_app_deletes_only_that_bundle(self):
        scrub.LSREGISTER = "/usr/bin/true"
        scrub.remove_app(self.old)
        self.assertFalse(self.old.exists())
        for survivor in (self.keep, self.prod, self.fresh, self.volume):
            self.assertTrue(survivor.exists())

    def test_symlink_is_manual(self):
        link = self.build / "link/Nextshot Dev.app"
        link.parent.mkdir(parents=True)
        link.symlink_to(self.old)
        app = scrub.read_app(link)
        self.assertEqual(scrub.decide(app, self.keep, [self.build], set()), "manual")

    def test_channels(self):
        self.assertEqual(scrub.read_app(self.old).channel, "dev")
        self.assertEqual(scrub.read_app(self.prod).channel, "production")
        rc = make_app(self.root, "RC.app", scrub.PRODUCTION_ID, "0.9.0-rc.1")
        self.assertEqual(scrub.read_app(rc).channel, "rc")


class BuildFolderTests(unittest.TestCase):
    """Build scripts must write app copies where Spotlight does not look."""

    def test_build_folders_end_in_noindex(self):
        local = (SCRIPTS / "build-local.sh").read_text()
        release = (SCRIPTS / "release-notarized.sh").read_text()
        self.assertIn('derived="$repo/build/local.noindex"', local)
        self.assertIn('work="$repo/build/release.noindex"', release)


if __name__ == "__main__":
    unittest.main()
