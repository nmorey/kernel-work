# Kernel Work Project Guidelines

Please adhere strictly to the following mandates and development workflows:

- **Build and Test Verification:** Always run `rake` (with no extra arguments) to verify the build, check for trailing whitespace, run unit tests, and build documentation before making any commit.
- **Documentation Coverage:** Maintain **100% YARD documentation coverage** at all times. All public, protected, and private classes, modules, constants, and methods must have high-quality YARD documentation comments.
- **Testing:** Always add comprehensive automated unit tests for any new features or bug fixes.
- **Shell Autocompletion:** All new commands and options must be updated and added to `kernel-work-completion.sh`.
