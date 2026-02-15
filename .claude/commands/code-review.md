Perform a code review of recent changes in this repository.

## Steps

1. **Identify changes to review:**
   ```bash
   git diff main --name-only
   git log main..HEAD --oneline
   ```

2. **Review each changed file** for:
   - **Security issues:** SQL injection, mass assignment, unvalidated input, exposed secrets
   - **Rails conventions:** proper use of scopes, callbacks, validations, strong parameters
   - **Code quality:** N+1 queries, missing indexes, unused variables, dead code
   - **Test coverage:** new code has corresponding tests, edge cases covered
   - **Error handling:** rescue blocks are specific, errors are logged appropriately

3. **Check for common anti-patterns:**
   - Business logic in controllers (should be in models or services)
   - Fat models without concerns or service objects
   - Missing database constraints that only exist as ActiveRecord validations
   - Hardcoded values that should be configuration

4. **Verify tests pass:**
   ```bash
   bundle exec rspec
   ```

5. **Check linting:**
   ```bash
   bin/rubocop
   ```

6. **Report findings** organized by severity:
   - **P0 (Critical):** Security vulnerabilities, data loss risks
   - **P1 (High):** Bugs, missing error handling, broken functionality
   - **P2 (Medium):** Performance issues, missing tests, convention violations
   - **P3 (Low):** Style issues, minor improvements, documentation gaps
