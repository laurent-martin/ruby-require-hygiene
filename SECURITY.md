# Security policy

## Supported versions

Only the latest released version of `require_hygiene` receives security fixes.

## Reporting a vulnerability

Do not open a public issue. Use the private reporting of GitHub:
[Report a vulnerability](https://github.com/laurent-martin/ruby-require-hygiene/security/advisories/new).

Give the version of the gem, the version of Ruby, and the steps to reproduce. You will get an answer within a few days,
and a fix and a coordinated disclosure when the report is confirmed.

## Scope

`require_hygiene` analyzes Ruby source files without executing them. The command `check-load` is the exception: it loads
each file in a new Ruby process, which executes the code of the analyzed project. Run it only on code that you trust.
