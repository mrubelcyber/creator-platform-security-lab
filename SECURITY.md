# Security Policy

Creator Platform is a security **training lab**. It is deliberately small and is not run as a production service.

## Reporting a vulnerability

Please report privately through **GitHub private vulnerability reporting**:
Security tab -> "Report a vulnerability". Do not open a public issue for security problems.

Include what you found, how to reproduce it, and the impact you expect.

## What to expect

- Acknowledgement within 5 working days.
- A fix, or a written risk decision, tracked against a SEC ticket.
- Credit in the fix commit if you want it.

## Scope

In scope: code, workflows and Terraform in this repository.
Out of scope: any AWS account, including the lab account. Do not test against cloud resources.

## How this repo protects itself

Every pull request runs SAST (Semgrep), secret scanning (Gitleaks + GitHub push protection),
dependency and container scanning with an SBOM (Trivy), IaC scanning (Checkov) and DAST (OWASP ZAP baseline + API).
Actions are pinned to full commit SHAs and updated by Dependabot. See the Lab 13 page for details.
