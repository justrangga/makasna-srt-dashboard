#!/usr/bin/env python3
"""
Google Drive Integration Service for Makasna Live Video Transport Gateway.
Handles OAuth 2.0 Web flow, token storage, folder hierarchy, and resumable file uploads.
"""

import os
import sys
import json
import time
import threading
from datetime import datetime, timezone

# Allow Google OAuth to return additional scopes (such as openid or previously granted scopes) without error
os.environ["OAUTHLIB_RELAX_TOKEN_SCOPE"] = "1"
os.environ["OAUTHLIB_INSECURE_TRANSPORT"] = "1"

try:
    from google.oauth2.credentials import Credentials
    from google.oauth2 import service_account
    from google_auth_oauthlib.flow import Flow
    from google.auth.transport.requests import Request
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaFileUpload
    GOOGLE_LIBS_AVAILABLE = True
except ImportError:
    GOOGLE_LIBS_AVAILABLE = False

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(BASE_DIR, "gdrive_config.json")
TOKEN_FILE = os.path.join(BASE_DIR, "gdrive_token.json")
SERVICE_ACCOUNT_FILE = os.path.join(BASE_DIR, "gdrive_service_account.json")
RECORDINGS_DIR = os.path.join(BASE_DIR, "recordings")
META_FILE = os.path.join(BASE_DIR, "recordings_meta.json")

os.makedirs(RECORDINGS_DIR, exist_ok=True)

SCOPES = [
    "https://www.googleapis.com/auth/drive.file",
    "https://www.googleapis.com/auth/userinfo.email"
]

DEFAULT_CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID", "")
DEFAULT_CLIENT_SECRET = os.environ.get("GOOGLE_CLIENT_SECRET", "")

gdrive_lock = threading.Lock()


def load_gdrive_config():
    cfg = {
        "client_id": DEFAULT_CLIENT_ID,
        "client_secret": DEFAULT_CLIENT_SECRET,
        "target_folder_name": "Makasna Video Archive",
        "target_folder_id": "",
        "connected_email": "",
        "connected": False,
        "auto_upload": True,
        "delete_after_upload": False
    }
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r") as f:
                saved = json.load(f)
                cfg.update(saved)
        except Exception:
            pass
    return cfg


def save_gdrive_config(cfg):
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)


def get_credentials():
    if not GOOGLE_LIBS_AVAILABLE:
        return None

    # 1. Check if Service Account JSON exists (highest stability, never expires)
    if os.path.exists(SERVICE_ACCOUNT_FILE):
        try:
            return service_account.Credentials.from_service_account_file(
                SERVICE_ACCOUNT_FILE,
                scopes=SCOPES
            )
        except Exception as e:
            print(f"[GDrive] Error loading service account: {e}")

    # 2. Check if OAuth Token exists
    cfg = load_gdrive_config()
    client_id = cfg.get("client_id") or DEFAULT_CLIENT_ID
    client_secret = cfg.get("client_secret") or DEFAULT_CLIENT_SECRET

    if not os.path.exists(TOKEN_FILE):
        return None

    try:
        with open(TOKEN_FILE, "r") as f:
            token_data = json.load(f)

        creds = Credentials(
            token=token_data.get("token"),
            refresh_token=token_data.get("refresh_token"),
            token_uri="https://oauth2.googleapis.com/token",
            client_id=client_id,
            client_secret=client_secret,
            scopes=SCOPES
        )

        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
            with open(TOKEN_FILE, "w") as f:
                json.dump({
                    "token": creds.token,
                    "refresh_token": creds.refresh_token,
                    "scopes": creds.scopes
                }, f, indent=2)

        return creds
    except Exception as e:
        print(f"[GDrive] Error loading credentials: {e}")
        return None


def save_service_account_json(json_content):
    if not GOOGLE_LIBS_AVAILABLE:
        raise RuntimeError("Google API libraries not installed.")

    if isinstance(json_content, str):
        data = json.loads(json_content)
    else:
        data = json_content

    client_email = data.get("client_email")
    if not client_email:
        raise ValueError("Invalid Service Account JSON: 'client_email' not found.")

    with open(SERVICE_ACCOUNT_FILE, "w") as f:
        json.dump(data, f, indent=2)

    cfg = load_gdrive_config()
    cfg["connected"] = True
    cfg["auth_mode"] = "service_account"
    cfg["connected_email"] = f"{client_email} (Service Account)"
    save_gdrive_config(cfg)

    return client_email



def get_auth_url(redirect_uri):
    if not GOOGLE_LIBS_AVAILABLE:
        raise RuntimeError("Google API libraries not installed on server.")

    cfg = load_gdrive_config()
    client_id = cfg.get("client_id") or DEFAULT_CLIENT_ID
    client_secret = cfg.get("client_secret") or DEFAULT_CLIENT_SECRET

    client_config = {
        "web": {
            "client_id": client_id,
            "client_secret": client_secret,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token"
        }
    }

    flow = Flow.from_client_config(
        client_config,
        scopes=SCOPES,
        redirect_uri=redirect_uri
    )

    auth_url, _ = flow.authorization_url(
        access_type="offline",
        include_granted_scopes="true",
        prompt="consent"
    )
    return auth_url


def exchange_code_for_token(code, redirect_uri):
    if not GOOGLE_LIBS_AVAILABLE:
        raise RuntimeError("Google API libraries not installed.")

    cfg = load_gdrive_config()
    client_id = cfg.get("client_id") or DEFAULT_CLIENT_ID
    client_secret = cfg.get("client_secret") or DEFAULT_CLIENT_SECRET

    client_config = {
        "web": {
            "client_id": client_id,
            "client_secret": client_secret,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token"
        }
    }

    flow = Flow.from_client_config(
        client_config,
        scopes=SCOPES,
        redirect_uri=redirect_uri
    )

    flow.fetch_token(code=code)
    creds = flow.credentials

    # Save token
    with open(TOKEN_FILE, "w") as f:
        json.dump({
            "token": creds.token,
            "refresh_token": creds.refresh_token,
            "scopes": creds.scopes
        }, f, indent=2)

    # Fetch user info email
    email = "Connected Google User"
    try:
        service_oauth = build("oauth2", "v2", credentials=creds, cache_discovery=False)
        user_info = service_oauth.userinfo().get().execute()
        email = user_info.get("email", email)
    except Exception:
        pass

    cfg["connected"] = True
    cfg["connected_email"] = email
    save_gdrive_config(cfg)

    return email


def disconnect_gdrive():
    cfg = load_gdrive_config()
    cfg["connected"] = False
    cfg["connected_email"] = ""
    cfg["auth_mode"] = "none"
    save_gdrive_config(cfg)
    if os.path.exists(TOKEN_FILE):
        try:
            os.remove(TOKEN_FILE)
        except Exception:
            pass
    if os.path.exists(SERVICE_ACCOUNT_FILE):
        try:
            os.remove(SERVICE_ACCOUNT_FILE)
        except Exception:
            pass
    return True


def get_or_create_folder(service, folder_name, parent_id=None):
    query = f"mimeType='application/vnd.google-apps.folder' and name='{folder_name}' and trashed=false"
    if parent_id:
        query += f" and '{parent_id}' in parents"
    else:
        query += " and 'root' in parents"

    results = service.files().list(q=query, spaces='drive', fields='files(id, name)').execute()
    files = results.get('files', [])

    if files:
        return files[0]['id']

    folder_metadata = {
        'name': folder_name,
        'mimeType': 'application/vnd.google-apps.folder'
    }
    if parent_id:
        folder_metadata['parents'] = [parent_id]

    folder = service.files().create(body=folder_metadata, fields='id').execute()
    return folder.get('id')


def upload_file_to_drive(file_path, route_name="General"):
    creds = get_credentials()
    if not creds:
        raise RuntimeError("Google Drive is not connected.")

    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File not found: {file_path}")

    filename = os.path.basename(file_path)
    file_size = os.path.getsize(file_path)

    service = build("drive", "v3", credentials=creds, cache_discovery=False)
    cfg = load_gdrive_config()

    root_folder_name = cfg.get("target_folder_name") or "Makasna Video Archive"
    root_id = get_or_create_folder(service, root_folder_name)

    # Subfolder per route
    route_folder_id = get_or_create_folder(service, route_name, parent_id=root_id)

    # Subfolder per Date (YYYY-MM-DD)
    date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    date_folder_id = get_or_create_folder(service, date_str, parent_id=route_folder_id)

    file_metadata = {
        'name': filename,
        'parents': [date_folder_id],
        'description': f'Recorded by Makasna Gateway from route {route_name}'
    }

    media = MediaFileUpload(
        file_path,
        mimetype='video/mp4',
        resumable=True,
        chunksize=2 * 1024 * 1024 # 2MB chunk
    )

    request_upload = service.files().create(
        body=file_metadata,
        media_body=media,
        fields='id, name, webViewLink, webContentLink, size'
    )

    response = None
    while response is None:
        status, response = request_upload.next_chunk()

    return {
        "file_id": response.get("id"),
        "name": response.get("name"),
        "view_link": response.get("webViewLink", f"https://drive.google.com/file/d/{response.get('id')}/view"),
        "size": response.get("size", file_size)
    }


# =========================================================================
# Local Recordings Metadata & Indexing
# =========================================================================
def load_recordings_meta():
    if os.path.exists(META_FILE):
        try:
            with open(META_FILE, "r") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}


def save_recordings_meta(meta):
    with open(META_FILE, "w") as f:
        json.dump(meta, f, indent=2)


def scan_local_recordings():
    meta = load_recordings_meta()
    updated = False

    # Try to load friendly route names from routes.json
    routes_map = {}
    routes_file = os.path.join(BASE_DIR, "routes.json")
    if os.path.exists(routes_file):
        try:
            with open(routes_file, "r") as f:
                rlist = json.load(f)
                routes_map = {r.get("id"): r.get("name") for r in rlist}
        except Exception:
            pass

    for root, dirs, files in os.walk(RECORDINGS_DIR):
        for fname in files:
            if not fname.endswith(".mp4"):
                continue
            fpath = os.path.join(root, fname)
            try:
                stat = os.stat(fpath)
            except Exception:
                continue

            rel_dir = os.path.relpath(root, RECORDINGS_DIR)
            route_id = rel_dir if rel_dir != "." else "general"
            friendly_name = routes_map.get(route_id) or route_id.replace("route_", "").upper()

            key = f"{route_id}/{fname}"
            if key not in meta:
                created_dt = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat()
                meta[key] = {
                    "id": key,
                    "filename": fname,
                    "filepath": fpath,
                    "route_id": route_id,
                    "route_name": friendly_name,
                    "size_bytes": stat.st_size,
                    "size_mb": round(stat.st_size / (1024 * 1024), 2),
                    "created_at": created_dt,
                    "completed": False,
                    "last_size": stat.st_size,
                    "last_checked": time.time(),
                    "gdrive_status": "local_only",
                    "gdrive_link": ""
                }
                updated = True
            else:
                # Update size and route name
                rec = meta[key]
                if rec.get("route_name") != friendly_name:
                    rec["route_name"] = friendly_name
                    updated = True

                if rec["size_bytes"] != stat.st_size:
                    rec["size_bytes"] = stat.st_size
                    rec["size_mb"] = round(stat.st_size / (1024 * 1024), 2)
                    rec["last_size"] = stat.st_size
                    rec["last_checked"] = time.time()
                    rec["completed"] = False
                    updated = True
                elif not rec.get("completed"):
                    # If size hasn't changed for 15 seconds, mark completed
                    if time.time() - rec.get("last_checked", time.time()) > 15:
                        rec["completed"] = True
                        if rec.get("gdrive_status") == "local_only":
                            rec["gdrive_status"] = "pending"
                        updated = True

    if updated:
        save_recordings_meta(meta)

    return meta

