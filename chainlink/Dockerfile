# Not using a multi-stage build since we don't care about image reuse 
# Image reuse: https://pmac.io/2019/02/multi-stage-dockerfile-and-python-virtualenv/)
# Just dump everything into the global python installation

FROM python:3.9-slim

# Setup env
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONFAULTHANDLER=1 \
    PYTHONHASHSEED=random \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DEFAULT_TIMEOUT=100 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    POETRY_VERSION=1.1.10

# Install poetry. Want poetry's dependencies to overwrite anything there already
RUN pip install  --ignore-installed "poetry==$POETRY_VERSION"

COPY . /app
WORKDIR /app

# Install packages without virtualenv. TODO(larryob): Don't install dev dependencies
RUN POETRY_VIRTUALENVS_CREATE=false poetry install --no-root


ENTRYPOINT [ "python", "app.py" ]