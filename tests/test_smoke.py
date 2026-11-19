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

    def test_multi_user_lifecycle(self):
        import app as app_module
        if os.path.exists(app_module.AUTH_CONFIG_FILE):
            os.remove(app_module.AUTH_CONFIG_FILE)
        # setup creates user1
        self.client.post("/setup", data={"username": "admin", "password": "adminpass123", "confirm_password": "adminpass123"})
        self.client.post("/login", data={"username": "admin", "password": "adminpass123"})
        # add user2 (requires admin password)
        r = self.client.post("/api/auth/users", json={"username": "operator2", "new_password": "operpass123", "admin_password": "adminpass123"})
        self.assertEqual(r.status_code, 200)
        # duplicate username rejected
        r = self.client.post("/api/auth/users", json={"username": "OPERATOR2", "new_password": "operpass123", "admin_password": "adminpass123"})
        self.assertEqual(r.status_code, 400)
        # list shows both
        r = self.client.get("/api/auth/users")
        names = [u["username"] for u in r.json["users"]]
        self.assertIn("admin", names)
        self.assertIn("operator2", names)
        # user2 can log in
        c2 = app_module.app.test_client()
        r = c2.post("/login", data={"username": "operator2", "password": "operpass123"})
        self.assertEqual(r.status_code, 302)
        # cannot delete self
        r = self.client.delete("/api/auth/users/admin")
        self.assertEqual(r.status_code, 400)
        # delete user2 works
        r = self.client.delete("/api/auth/users/operator2")
        self.assertEqual(r.status_code, 200)
        # user2 login now fails
        r = c2.post("/login", data={"username": "operator2", "password": "operpass123"})
        self.assertIn(b"Invalid username or password", r.data)
        # legacy single-account shape migrates
        import json
        legacy = {"username": "legacy", "password_hash": app_module.generate_password_hash("legacy123"), "setup_complete": True, "updated_at": "x"}
        with open(app_module.AUTH_CONFIG_FILE, "w") as f:
            json.dump(legacy, f)
        cfg = app_module.load_auth_config()
        self.assertEqual(len(cfg["users"]), 1)
        self.assertEqual(cfg["users"][0]["username"], "legacy")
        c3 = app_module.app.test_client()
        r = c3.post("/login", data={"username": "legacy", "password": "legacy123"})
        self.assertEqual(r.status_code, 302)

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
        self.assertEqual(cfg["users"][0]["username"], "operator")
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
