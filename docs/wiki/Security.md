# Security

- Generate a unique `SECRET_KEY` per installation.
- Set a unique dashboard password; never use a repository default or example value.
- Keep `/etc/makasna-dashboard.env` mode `600` and owned by `root`.
- Bind MediaMTX API to `127.0.0.1` and do not expose port `9997` publicly.
- Allow only required ports in UFW or the cloud security group.
- Prefer HTTPS through a reverse proxy when the dashboard is accessed over an untrusted network.
- Use SRT passphrases where the transport crosses an untrusted network; store them only in protected local configuration.
- Do not commit stream keys, tokens, passwords, private keys, service-account files, or connection strings.
- Rotate credentials after staff or infrastructure changes.
- Review `journalctl` and application logs for accidental secret exposure before publishing diagnostics.
