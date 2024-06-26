forge coverage --report lcov
genhtml lcov.info --branch-coverage --output-dir docs/coverage --ignore-errors inconsistent
