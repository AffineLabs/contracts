forge coverage --report lcov
genhtml lcov.info --branch-coverage --output-dir coverage --ignore-errors inconsistent
