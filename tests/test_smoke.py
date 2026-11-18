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
        self.assertEqual(response.status_code, 401)


if __name__ == "__main__":
    unittest.main()
