# Security Policy

## Supported Versions

RodaAi follows a rolling release model. Only the latest version on the `main` branch receives security updates.

| Version | Supported |
|---------|-----------|
| Latest `main` | Yes |
| Older commits | No |

## Architecture and Threat Model

RodaAi runs AI inference entirely on-device. There is no backend server, no user accounts, and no cloud API. The only network activity is downloading models from Hugging Face Hub.

**What is in scope:**
- Vulnerabilities in model loading or parsing that could lead to code execution
- Issues in the Hugging Face download pipeline (e.g., MITM, path traversal)
- SwiftData or Keychain misuse that could expose user data
- Memory safety issues in the inference layer (MLX, llama.cpp bindings)
- Improper file handling that could escape the app sandbox

**What is out of scope:**
- Model output quality or accuracy (prompt injection in LLM responses)
- Vulnerabilities in upstream dependencies (report those to the respective projects)
- Physical device access scenarios (device security is Apple's responsibility)
- Issues requiring jailbroken devices

## Reporting a Vulnerability

Open an issue on the [GitHub repository](https://github.com/bmtec-us/roda.ai/issues) describing the vulnerability, steps to reproduce, and affected components if known.

This is a GPL-3.0 open source project maintained in my free time. There are no guaranteed response times or SLAs. Issues will be reviewed and fixed as I can, but no commitments on timelines.

## Privacy Commitment

RodaAi collects zero telemetry and has zero network activity during inference. All conversation data is stored locally with `NSFileProtectionComplete` encryption. The Hugging Face access token, if configured, is stored in the iOS/macOS Keychain — never in plaintext. See our [README](../README.md) for the full privacy model.
