import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile


class PackageTests(unittest.TestCase):
    def setUp(self):
        script = Path(__file__).resolve().parents[1] / "scripts/package.py"
        self.assertTrue(script.is_file(), "local package builder must exist")
        spec = importlib.util.spec_from_file_location("package", script)
        self.builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.builder)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "addon"
        self.root.mkdir()
        (self.root / "Murgle.toc").write_text("## Version: 0.1.0-dev\nCore.lua\n")
        (self.root / "Core.lua").write_text("-- runtime\n")
        (self.root / "LICENSE").write_text("All rights reserved.\n")
        (self.root / "Media").mkdir()
        (self.root / "Media/MurgleIcon.tga").write_bytes(b"icon")
        self.output = Path(self.temp.name) / "Murgle.zip"

    def test_only_runtime_icon_and_license_are_packaged_reproducibly(self):
        (self.root / "notes.txt").write_text("private")
        (self.root / "Media/private.txt").write_text("private")
        self.builder.build(self.root, self.output)
        original = self.output.read_bytes()
        with zipfile.ZipFile(self.output) as archive:
            self.assertEqual(set(archive.namelist()), {
                "Murgle/Murgle.toc", "Murgle/Core.lua", "Murgle/Media/MurgleIcon.tga", "Murgle/LICENSE"
            })
            self.assertEqual(archive.read("Murgle/Core.lua"), b"-- runtime\n")
        self.output.unlink()
        self.builder.build(self.root, self.output)
        self.assertEqual(original, self.output.read_bytes())

    def test_missing_input_leaves_no_archive(self):
        (self.root / "Core.lua").unlink()
        with self.assertRaises(ValueError):
            self.builder.build(self.root, self.output)
        self.assertFalse(self.output.exists())

    def test_rejects_traversal_private_files_and_symlinks(self):
        for entry in ("../outside.lua", "/outside.lua", "docs/notes.lua", "notes.txt"):
            with self.subTest(entry=entry):
                (self.root / "Murgle.toc").write_text(entry + "\n")
                with self.assertRaises(ValueError):
                    self.builder.build(self.root, self.output)
                self.assertFalse(self.output.exists())
        (self.root / "Murgle.toc").write_text("Core.lua\n")
        (self.root / "Core.lua").unlink()
        (self.root / "Core.lua").symlink_to(self.root / "Media/MurgleIcon.tga")
        with self.assertRaises(ValueError):
            self.builder.build(self.root, self.output)

    def test_existing_output_is_not_overwritten(self):
        self.output.write_bytes(b"existing")
        with self.assertRaises(FileExistsError):
            self.builder.build(self.root, self.output)
        self.assertEqual(self.output.read_bytes(), b"existing")


if __name__ == "__main__":
    unittest.main()
