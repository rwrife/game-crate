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

    def test_provisioning_errors_have_fixed_actionable_subcategories(self):
        examples = [
            ("Your account has reached the maximum number of certificates: private@example.com", "certificate-quota"),
            ("No profiles for 'com.infinityball.gamecrate' were found: TEAMSECRET", "missing-profiles"),
            ("Automatic signing is disabled and unable to generate a profile. secret-key", "automatic-signing-disabled"),
            ("No Accounts: Add a new account in Accounts settings. private@example.com", "missing-account"),
            ("Authentication credentials are missing or invalid: secret-key", "invalid-credentials"),
            ("error: Swift compile failed: unknown private text", "compiler-or-build"),
        ]
        for log, category in examples:
            with self.subTest(category=category):
                self.assertEqual(summarize(log), f"Xcode failure categories: {category}=1")

    def test_specific_categories_do_not_echo_credential_fragments(self):
        log = ("No profiles for 'private-key-fragment' were found: signer@example.com\n"
               "Authentication credentials are missing or invalid: ISSUER-UUID\n"
               "Automatic signing is disabled and unable to generate a profile: TEAM123\n")
        self.assertEqual(summarize(log), "Xcode failure categories: missing-profiles=1, "
                         "automatic-signing-disabled=1, invalid-credentials=1")
        for fragment in ("private-key-fragment", "signer@example.com", "ISSUER-UUID", "TEAM123"):
            self.assertNotIn(fragment, summarize(log))

    def test_platform_and_destination_blockers_have_specific_categories(self):
        self.assertEqual(summarize("error: iOS 26.0 is not installed. Please download and install the platform secret123"),
                         "Xcode failure categories: missing-ios-platform=1")
        self.assertEqual(summarize("error: Unable to find a destination matching the provided destination specifier private123"),
                         "Xcode failure categories: missing-destination=1")

    def test_unknown_failure_is_explicit_without_raw_excerpt(self):
        self.assertIn("no classified error", summarize("quiet failure; secret=123"))
        self.assertNotIn("123", summarize("quiet failure; secret=123"))


if __name__ == "__main__":
    unittest.main()
