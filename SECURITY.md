# Security Policy

Nabby handles SSH credentials, so we take security reports seriously.

## Reporting a vulnerability

**Do not open a public issue.** Report privately through
[GitHub Security Advisories](https://github.com/Black-Ring-Security/nabby/security/advisories/new).

Please include the Nabby version, Android version, and steps to reproduce.
We aim to acknowledge reports within 72 hours and to ship a fix for confirmed
issues as soon as possible.

## Supported versions

Only the latest release receives security fixes.

## Scope

In scope: credential storage, host key verification, SSH/SFTP handling, port forwarding,
anything that could leak secrets or let a malicious server affect the phone.
