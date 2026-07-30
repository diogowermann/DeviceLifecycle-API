# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows semantic versioning for its HTTP contract.

## [Unreleased]

### Added

- English portfolio-oriented `README.md`.
- Complete Portuguese `README.pt-BR.md`.
- English and Portuguese HTTP API contracts under `docs/en/` and `docs/pt-BR/`.
- English and Portuguese architecture documentation with Mermaid diagrams.
- MIT license.
- Security policy covering vulnerability reporting, deployment controls, key exposure, dependencies, and data handling.
- Explicit image placeholders for future sanitized test-environment evidence.

### Changed

- Reorganized documentation around the API's read-only responsibility boundary.
- Expanded documentation for authentication, stable file reads, path safety, network controls, failure behavior, runtime configuration, and key rotation.
- Preserved legacy `docs/API.md` and `docs/ARCHITECTURE.md` paths as language-selection pages.

## [1.0.0] - 2026-07-29

### Added

- Initial read-only FastAPI service.
- CSV, JSON, metadata, log-tail, complete-log, and health endpoints under `/api/v1`.
- API-key authentication through `X-API-Key`.
- PowerShell installation, startup, validation, key-rotation, and uninstallation scripts.
- Windows Scheduled Task deployment and restricted firewall-rule management.
- Runtime configuration outside the repository.
- Rotating API request logs.
- Initial Portuguese README, API contract, and architecture documentation.
