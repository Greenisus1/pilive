import json, pathlib, subprocess, unittest, os, tempfile
ROOT = pathlib.Path(__file__).resolve().parent
class Packaging(unittest.TestCase):
    def test_headless_menu(self):
        with tempfile.TemporaryDirectory() as home:
            env=dict(os.environ, HOME=home, DISPLAY="", WAYLAND_DISPLAY="")
            result=subprocess.run(["bash", "pilive.sh"], cwd=ROOT, input="7\n", text=True, env=env, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0)
            self.assertIn("Choice:", result.stdout)
    def test_headless_status(self):
        with tempfile.TemporaryDirectory() as home:
            env=dict(os.environ, HOME=home, DISPLAY="", WAYLAND_DISPLAY="")
            result=subprocess.run(["bash", "pilive.sh", "status"], cwd=ROOT, text=True, env=env, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0)
    def test_config_is_data_only(self):
        with tempfile.TemporaryDirectory() as home:
            h=pathlib.Path(home); target=h/"injected"
            (h/".pilive.conf").write_text('STREAM_KEY=$(touch '+str(target)+')\n')
            env=dict(os.environ, HOME=home, DISPLAY="", WAYLAND_DISPLAY="")
            r=subprocess.run(["bash", "pilive.sh", "config"], cwd=ROOT, input="\n"*11, text=True, env=env, capture_output=True, timeout=5)
            self.assertEqual(r.returncode,0)
            self.assertFalse(target.exists())
            self.assertNotIn(str(target),r.stdout)
            self.assertEqual((h/".pilive.conf").stat().st_mode & 0o777,0o600)
    def test_headless_start_rejected(self):
        with tempfile.TemporaryDirectory() as home:
            h=pathlib.Path(home); (h/".pilive.conf").write_text("STREAM_KEY=test-not-real\n")
            bindir=h/"bin";bindir.mkdir(); stub=bindir/"ffmpeg";stub.write_text("#!/bin/sh\nexit 99\n");stub.chmod(0o700)
            env=dict(os.environ, HOME=home, DISPLAY="", WAYLAND_DISPLAY="", PATH=str(bindir)+":"+os.environ["PATH"])
            r=subprocess.run(["bash", "pilive.sh", "start"],cwd=ROOT,env=env,capture_output=True,text=True)
            self.assertNotEqual(r.returncode,0)
            self.assertIn("X11",r.stderr)
            self.assertFalse((h/".pilive.pid").exists())
    def test_syntax(self):
        for path in ROOT.glob("*.sh"):
            self.assertEqual(subprocess.run(["bash", "-n", str(path)], capture_output=True).returncode, 0, path.name)
    def test_marker(self):
        self.assertIn("# pi-app-store: 1", (ROOT/"app-store.sh").read_text().splitlines()[:5])
    def test_version(self):
        self.assertEqual(json.loads((ROOT/"app-version.json").read_text())["version"], "1.0.1")
    def test_safe_install(self):
        self.assertEqual(subprocess.run(["bash", "app-store.sh", "install"], cwd=ROOT, capture_output=True).returncode, 0)
    def test_entry(self):
        self.assertTrue((ROOT/"pilive.sh").is_file())
if __name__ == "__main__": unittest.main()
