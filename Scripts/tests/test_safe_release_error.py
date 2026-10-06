import unittest
from Scripts.safe_release_error import summarize


class ReleaseDiagnosticsTests(unittest.TestCase):
    def test_never_echoes_full_or_partial_credentials(self):
        fragments = ["KEYID1234", "ISSUER-UUID", "TEAM123", "AbCd1234==", "ZYXWVUTS", "signer@example.com"]
        log = "\n".join(f"error: provisioning profile key fragment {secret}" for secret in fragments)
        report = summarize(log)
        self.assertEqual(report, "Xcode failure categories: provisioning=6")
        for secret in fragments:
            self.assertNotIn(secret, report)

    def test_classifies_without_echoing_xcode_lines(self):
        report = summarize("No signing certificate for private@example.com\n"
                           "error: authentication failed for secret-123\n"
                           "error: unknown secret payload\n")
        self.assertEqual(report, "Xcode failure categories: signing-certificate=1, "
                         "appstore-auth=1, compiler-or-build=1")
        self.assertNotIn("secret", report)

    def test_unknown_failure_is_explicit_without_raw_excerpt(self):
        self.assertIn("no classified error", summarize("quiet failure; secret=123"))
        self.assertNotIn("123", summarize("quiet failure; secret=123"))


if __name__ == "__main__":
    unittest.main()
