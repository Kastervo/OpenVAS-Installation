# Contributing to OpenVAS Installation

Thank you for your interest in contributing to the OpenVAS Installation project! This repository hosts a script to automate the installation of OpenVAS (Greenbone Community Edition) on Debian 12 systems. We appreciate community feedback to improve the script and documentation, and we welcome your suggestions to enhance the project’s quality and security.

To maintain consistency and ensure alignment with our project goals, **we do not accept pull requests**. Instead, we encourage contributors to submit issues to report bugs, suggest enhancements, or propose documentation improvements. Our maintainers will review these issues and implement the approved changes ourselves. This document outlines the guidelines for contributing via issues.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How to Contribute](#how-to-contribute)
	- [Reporting Bugs](#reporting-bugs)
	- [Suggesting Enhancements](#suggesting-enhancements)
	- [Improving Documentation](#improving-documentation)
- [Development Setup](#development-setup)
- [Issue Submission Process](#issue-submission-process)
- [Style Guidelines](#style-guidelines)
	- [Bash Script Style](#bash-script-style)
	- [Documentation Style](#documentation-style)
- [Testing](#testing)
- [License](#license)
- [Contact](#contact)

## Code of Conduct

This project adheres to a Code of Conduct. By participating, you are expected to uphold this code, fostering an open, inclusive, and respectful environment for all contributors.

## How to Contribute

We welcome contributions in the form of issues to report bugs, suggest enhancements, or propose documentation improvements. **We do not accept pull requests**, as all changes are implemented by our maintainers to ensure consistency and adherence to project standards. Below are the ways you can contribute:

### Reporting Bugs

If you encounter a bug or issue with the script, please report it:

- **Check Existing Issues**: Ensure the bug hasn’t already been reported by searching the Issues page.
- **Open a New Issue**: Use the bug report template provided in the repository. Include:
	- A clear and descriptive title.
	- Steps to reproduce the issue.
	- Expected and actual behavior.
	- Relevant logs (e.g., from `/var/log/openvas_install.log`).
	- System details (e.g., Debian version, hardware specs).
- **Label the Issue**: Apply the `bug` label to help us prioritize it.

### Suggesting Enhancements

We welcome ideas to improve the script or its functionality:

- **Search for Duplicates**: Check the Issues page to avoid submitting duplicate suggestions.
- **Use the Enhancement Template**: Submit your idea via an issue using the enhancement template. Include:
	- A detailed description of the proposed feature or improvement.
	- Use cases or benefits of the enhancement.
	- Any potential challenges or considerations.
- **Label the Issue**: Apply the `enhancement` label.

### Improving Documentation

Documentation improvements are highly valued, including updates to `README.md`, `CONTRIBUTING.md`, or inline script comments:

- **Open an Issue**: Propose documentation changes via an issue, describing the suggested edits or additions.
- **Provide Details**: Include specific suggestions, such as corrected text, new sections, or improved examples.
- **Label the Issue**: Apply the `documentation` label.
- **Focus Areas**: Clarify instructions, fix typos, improve examples, or add troubleshooting tips.

## Development Setup

If you want to test the script or reproduce issues locally to provide detailed feedback:

1. **Prepare a Debian 12 System**:

	- Use a clean, fully updated Debian 12 installation (physical, virtual, or containerized).
	- Ensure root access and internet connectivity.
	- Allocate at least 1GB of free disk space for source, build, and install directories.

2. **Clone the Repository**:

	```bash
	git clone https://github.com/Kastervo/OpenVAS-Installation.git
	cd OpenVAS-Installation
	```

3. **Install Dependencies**:

	- Run the script’s dependency installation step to ensure required tools are available:

	```bash
	./openvas_install.sh
	```

	- Stop after the `install_packages` function to avoid full installation during testing.

4. **Test the Script**:

	- Run the script or specific functions to reproduce issues or verify behavior.
	- Document your findings in the issue (see Testing).

## Issue Submission Process

To contribute, follow these steps to submit an issue:

1. **Open an Issue**:

	- Use the appropriate issue template (`bug`, `enhancement`, or `documentation`).
	- Provide a clear description, including:
		- **For bugs**: Steps to reproduce, expected vs. actual behavior, logs, and system details.
		- **For enhancements**: Detailed explanation, use cases, and potential challenges.
		- **For documentation**: Specific changes, corrected text, or new content suggestions.
	- Apply the correct label (`bug`, `enhancement`, or `documentation`).

2. **Discuss with Maintainers**:

	- Maintainers will review your issue and may request additional details or clarification.
	- Engage in the discussion to refine the proposal or confirm the issue.
	- Approved issues will be prioritized for implementation by the maintainers.

3. **Implementation by Maintainers**:

	- Once an issue is approved, maintainers will implement the changes in the `master` branch.
	- You may be asked to test the implemented changes in a future release to confirm they address your issue.

	**Note**: **We do not accept pull requests**. Any pull requests submitted will be closed with a request to open an issue instead. This ensures all changes are thoroughly vetted and implemented consistently by our team.

## Style Guidelines

To help maintainers implement your suggestions, please align your issue descriptions with our style guidelines where applicable.

### Bash Script Style

For bug reports or enhancement suggestions related to `openvas_install.sh`:

- **Reference ShellCheck**: If suggesting code changes, ensure they pass `shellcheck` checks.
- **Formatting**:
	- Suggest 4-space-sized tabs indentation.
	- Recommend breaking long lines at logical points (max 80 characters where possible).
- **Comments**:
	- Suggest comments before functions to explain their purpose.
	- Recommend inline comments for complex logic.
	- Include references to Greenbone documentation (e.g., `URL: https://greenbone.github.io/...`) if relevant.
- **Logging**:
	- Suggest using the `log` function for all output (`INFO`, `WARN`, `ERROR`).
	- Recommend clear messages with relevant details (e.g., paths, error codes).
- **Error Handling**:
	- Suggest using `run_command` for commands that require error checking.
	- Recommend exiting with appropriate status codes on failure.
- **Security**:
	- Emphasize least privilege (e.g., restrict file permissions, use `gvm` user).
	- Suggest validating inputs and external data (e.g., GPG signatures).
	- Align with certain compliance frameworks where applicable.

### Documentation Style

For documentation-related issues:

- **Format**:
	- Suggest proper Markdown syntax (e.g., `#` for headings, `**` for bold).
	- Recommend keeping lines under 80 characters.
	- Suggest bullet points or numbered lists for clarity.
- **Tone**:
	- Recommend clear, concise, and professional language.
	- Avoid jargon unless defined.
- **Structure**:
	- Suggest including a table of contents for longer documents.
	- Recommend logical organization (e.g., prerequisites before usage).
- **Examples**:
	- Provide complete, testable code snippets (e.g., `sudo ./openvas_install.sh`).
	- Suggest fenced code blocks (`bash ... `).
- **Links**:
	- Recommend referencing Greenbone documentation or authoritative sources.
	- Ensure URLs are valid and use HTTPS.

## Testing

When submitting issues, include detailed testing information to help maintainers reproduce and address them:

- **Test Environment**:
	- Use a fresh Debian 12 installation (VM or container recommended).
	- Reset the environment between tests to avoid residual changes.
- **Test Cases**:
	- For bugs: Provide steps to reproduce the issue and expected vs. actual behavior.
	- For enhancements: Describe how the feature should work and any test scenarios.
	- For documentation: Suggest how to verify the clarity or accuracy of the proposed changes.
- **Log Review**:
	- Include relevant excerpts from `/var/log/openvas_install.log` for bugs.
	- Note any missing or unclear log messages.
- **Security**:
	- Highlight any permission issues (e.g., incorrect `gvm:gvm` ownership).
	- Confirm whether GPG signature verification or SSL certificate generation behaves as expected.
- **Screenshots or Outputs**:
	- If applicable, include terminal outputs, error messages, or screenshots in the issue.

## License

By contributing to this project, you agree that your suggestions and feedback will be incorporated under the Apache License 2.0. Ensure your contributions comply with the license terms.

## Contact

For questions or support, contact the maintainers via:

- **GitHub Issues**: Open an issue for bugs, enhancements, or documentation suggestions.
- **Website**: https://kastervo.com/.

Thank you for contributing to the OpenVAS Installation project! Your feedback and ideas help make vulnerability scanning more accessible and secure for everyone.