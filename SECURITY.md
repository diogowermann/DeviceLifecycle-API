# Security Policy

## Reporting a Vulnerability

Do not disclose suspected vulnerabilities, exposed API keys, credentials, certificates, internal addresses, or environment-specific configuration in a public issue.

Report the problem privately to the repository owner through an appropriate private GitHub or professional contact channel. Include:

- the affected component or endpoint;
- the observed behavior;
- reproduction steps;
- the potential impact;
- relevant logs with secrets and organization-specific data removed;
- a proposed remediation, when available.

Do not include a valid API key, tenant identifier, certificate private key, internal hostname, public IP address, or production data in the report.

## Supported Versions

The repository currently documents the `v1` HTTP contract and API version `1.0.0`. Security fixes are expected to target the latest code on the default branch unless a release policy states otherwise.

## Deployment Security Requirements

DeviceLifecycle-API publishes operational device data and logs. Treat its output as internal information.

Before deployment:

1. Review `DeviceLifecycleApi.Config.psd1` and replace all example values.
2. Configure explicit approved addresses in `RemoteAddress`.
3. Confirm that the generated inbound firewall rule does not allow broader access than intended.
4. Keep the API key outside source control, documentation, screenshots, tickets, and chat messages.
5. Restrict permissions on the runtime configuration and installation directories.
6. Confirm that the service account context requires only read access to DeviceLifecycle reports and logs.
7. Protect `/api/v1/health` with authentication when source availability or host identity should not be exposed.
8. Use HTTPS through a reverse proxy when traffic leaves a strictly trusted internal network.
9. Validate the installation with `Test-DeviceLifecycleApi.ps1` before connecting production consumers.
10. Establish an API-key rotation and consumer-update procedure.

## Security Boundaries

The project is designed around these controls:

- read-only HTTP endpoints;
- no direct connection to Active Directory, Entra ID, Intune, or Microsoft Graph;
- API-key authentication for data endpoints;
- constant-time key comparison;
- no client-supplied filesystem paths;
- rejection of unsafe configured relative paths;
- stable file reads to avoid partially written responses;
- host firewall restriction to approved consumers;
- disabled Swagger UI, ReDoc, and OpenAPI schema at runtime;
- `Cache-Control: no-store` and `X-Content-Type-Options: nosniff` response headers;
- rotating request logs that do not record the API key.

These controls do not replace network segmentation, secret management, host hardening, patching, monitoring, backups, or environment-specific review.

## Secret Exposure Response

If an API key may have been exposed:

1. run `Reset-DeviceLifecycleApiKey.ps1` immediately;
2. update every authorized consumer;
3. restart or validate the Scheduled Task;
4. review API request logs and firewall logs for unexpected clients;
5. remove the exposed value from documents, tickets, screenshots, or repository history where applicable;
6. assess whether the exposed reports or logs contained additional sensitive information.

If a private certificate key, administrative credential, or another environment secret is exposed, follow the corresponding organizational incident-response and rotation procedure.

## Dependency Security

Python dependencies are installed from the configured package source during installation. In controlled environments:

- use an approved internal package mirror when available;
- review dependency versions before deployment;
- rebuild the virtual environment after security-relevant dependency updates;
- test the API contract after updates;
- do not install unreviewed packages into the service virtual environment.

## Data Handling

Reports and logs can contain device names, activity timestamps, lifecycle results, and operational errors. Consumers must apply appropriate access control, retention, logging, and data-classification requirements.

The API does not provide field-level filtering. Any consumer with access to a data endpoint can retrieve the complete corresponding artifact.

## Out of Scope

Public reports without reproducible security impact, unsupported environment customizations, and vulnerabilities caused solely by intentionally disabling documented controls may be closed without remediation.
