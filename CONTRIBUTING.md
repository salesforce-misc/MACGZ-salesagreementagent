# Contributing to Sales Agreement Agent

Thank you for your interest in contributing to the Sales Agreement Agent project. This document explains how to report bugs, suggest changes, and send pull requests.

## Code of Conduct

This project adheres to the Salesforce Open Source Community Code of Conduct. By participating, you are expected to uphold this code.

## How to Contribute

### Reporting Bugs

If you find a bug, open an issue with:

- A clear, descriptive title
- Steps to reproduce the issue
- Expected vs. actual behavior
- Salesforce org edition and API version
- Any relevant error messages or logs

### Suggesting Enhancements

Open an issue with:

- A clear description of the enhancement
- The use case or problem it would solve
- Any examples if applicable

### Pull Requests

1. Fork the repository and create a new branch from `main`
2. Make your changes following the coding standards below
3. Write or update tests to cover your changes
4. Update documentation if needed
5. Ensure all tests pass before submitting
6. Submit a pull request with a clear description of the changes

### Coding Standards

- Follow Salesforce Apex best practices
- Maintain test coverage above 85%
- Follow the existing code style and naming conventions
- Add comments for complex logic
- Update relevant documentation

### Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/salesforce-misc/MACGZ-salesagreementagent.git
   cd MACGZ-salesagreementagent
   ```
2. Log in to a Salesforce org that has Manufacturing Cloud and Agentforce:
   ```bash
   sf org login web --alias my-mfg-org
   ```
3. Deploy the Apex, settings, permission set, and agent bundle, and run the tests:
   ```bash
   sf project deploy start -x manifest/package.xml -o my-mfg-org -l RunSpecifiedTests \
     --tests SaaSalesAgreementActionsTest --tests SaaApplyPriceIncreaseTest \
     --tests SaaSummarizeSalesAgreementTest --tests SaaAccountPlanObjectiveTest \
     --tests SaaGroundAndLogTest
   ```
4. Publish and activate the agent, then deploy the agent-access permission set. See [README.md](README.md).

### Testing Requirements

- All new Apex must include test classes
- Test classes should keep coverage above 85%
- Tests should cover both positive and negative scenarios
- Tests should use standard objects and fields, as the existing suite does

### Documentation

- Update `README.md` for user-facing changes
- Add inline comments for complex logic
- Update this `CONTRIBUTING.md` if the contribution process changes

### Commit Messages

Use clear, descriptive commit messages:

- Start with a verb (Add, Fix, Update, Remove)
- Keep the first line under 72 characters

## Questions?

If you have questions about contributing, open an issue or review the documentation in `docs/`.

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.
