import base64
from datetime import datetime, timezone
import tempfile
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

from Scripts import asc_build_evidence as release


class ReleaseEvidenceTests(unittest.TestCase):
    def test_der_signature_converts_to_jws_raw_and_rejects_trailing_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            key = Path(directory) / "test.p8"
            subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey",
                            "-noout", "-out", str(key)], check=True, capture_output=True)
            token = release.jwt(key, "test-key-id", "test-issuer")
            header, body, signature = token.split(".")
            self.assertEqual(len(base64.urlsafe_b64decode(signature + "==")), 64)
            self.assertTrue(header and body)
        with self.assertRaises(ValueError):
            release.der_signature_to_raw(b"\x30\x06\x02\x01\x01\x02\x01\x01x")

    def test_exact_new_build_only(self):
        started = datetime(2026, 10, 5, tzinfo=timezone.utc)
        builds = [
            {"id": "old", "attributes": {"version": "23", "uploadedDate": "2026-10-04T23:59:59Z", "processingState": "VALID"}},
            {"id": "wrong", "attributes": {"version": "24", "uploadedDate": "2026-10-05T00:00:02Z", "processingState": "VALID"}},
            {"id": "new", "attributes": {"version": "23", "uploadedDate": "2026-10-05T00:00:01Z", "processingState": "PROCESSING"}},
        ]
        found = release.select_build(builds, "23", started)
        self.assertIsNotNone(found)
        self.assertEqual(found["id"] if found else None, "new")
        self.assertIsNone(release.select_build(builds[:2], "23", started))

    def test_polls_to_valid_and_writes_actual_build_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "processed.json"
            api_response = [
                [{"id": "app-id", "attributes": {"bundleId": "com.infinityball.gamecrate"}}],
                [{"id": "build-id", "attributes": {"version": "9", "uploadedDate": "2026-10-05T12:01:00Z", "processingState": "PROCESSING"}}],
                [{"id": "build-id", "attributes": {"version": "9", "uploadedDate": "2026-10-05T12:01:00Z", "processingState": "VALID"}}],
            ]
            argv = ["script", "--key-path", str(Path(directory) / "unused.p8"),
                    "--key-id", "test", "--issuer-id", "test", "--bundle-id", "com.infinityball.gamecrate",
                    "--build-number", "9", "--started-at", "2026-10-05T12:00:00Z",
                    "--evidence", str(evidence), "--attempts", "2", "--interval", "0"]
            with patch("sys.argv", argv), patch.object(release, "api", side_effect=api_response):
                release.main()
            import json
            self.assertEqual(json.loads(evidence.read_text())["processing_state"], "VALID")
            self.assertEqual(json.loads(evidence.read_text())["build_id"], "build-id")


if __name__ == "__main__":
    unittest.main()
