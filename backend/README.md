# backend

Backend API for web dapp.

# Setup

1. Run `make firstrun` (installs poetry and all requirements). NOTE: requires python 3.9 setup
2. Run `make` in the future which only installs pipenv requirements
3. In the future only change `Pipfile` and discuss with the team about impending changes
4. <Docker setup instructions here>

# Run Server

Run `poetry run server` from the root of this directory (`/backend`).

# Docker and Testing

TODO: @Nadim

# General Good Practices:

1. NEVER work off of master (unless first commits), make a feature branch
2. Once you are reasonably done with commits, push to github for a code review
3. Once we review them, you are good to merge
4. NEVER commit credentials and add them to the `.gitignore` file
