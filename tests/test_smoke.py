import os
import unittest


class DashboardSmokeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ.setdefault("SECRET_KEY", "test-only-secret")
        os.environ.setdefault("DASHBOARD_USER", "test-admin")
        os.environ.setdefault("DASHBOARD_PASS", "test-password")
        from app import app
        cls.app = app
        cls.client = app.test_client()

    def test_login_page_is_available(self):
        response = self.client.get("/login")
        self.assertEqual(response.status_code, 200)

    def test_unauthenticated_api_is_rejected(self):
        response = self.client.get("/api/routes")
        self.assertIn(response.status_code, (401, 403))
        if response.status_code == 403:
            self.assertTrue(response.json.get("setup_required"))

    def test_setup_wizard_shown_before_first_run(self):
        import app as app_module
        if os.path.exists(app_module.AUTH_CONFIG_FILE):
            os.remove(app_module.AUTH_CONFIG_FILE)
        response = self.client.get("/")
        self.assertEqual(response.status_code, 302)
        self.assertTrue(response.location.endswith("/setup"))
        page = self.client.get("/setup")
        self.assertEqual(page.status_code, 200)
        self.assertIn(b"Secure Your Gateway", page.data)

    def test_setup_wizard_creates_credentials_and_login_works(self):
        import app as app_module
        if os.path.exists(app_module.AUTH_CONFIG_FILE):
            os.remove(app_module.AUTH_CONFIG_FILE)
        response = self.client.post("/setup", data={
            "username": "operator",
            "password": "supersecret123",
            "confirm_password": "supersecret123",
        }, follow_redirects=False)
        self.assertEqual(response.status_code, 302)
        cfg = app_module.load_auth_config()
        self.assertIsNotNone(cfg)
        self.assertEqual(cfg["username"], "operator")
        # login with new credentials
        login = self.client.post("/login", data={
            "username": "operator",
            "password": "supersecret123",
        })
        self.assertEqual(login.status_code, 302)
        # wizard no longer reachable
        self.assertEqual(self.client.get("/setup").status_code, 302)


if __name__ == "__main__":
    unittest.main()
