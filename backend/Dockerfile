FROM python:3.9-slim as base

# Setup env
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONFAULTHANDLER=1 \
    PYTHONHASHSEED=random \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1


FROM base AS python-deps

# Install poetry and compilation depedencies
ENV PIP_DEFAULT_TIMEOUT=100 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    POETRY_VERSION=1.1.10

RUN apt-get update && apt-get install -y --no-install-recommends build-essential gcc
RUN pip install "poetry==$POETRY_VERSION"

# # Install python dependencies into a single folder /venv
RUN python -m venv /venv
COPY poetry.lock pyproject.toml ./

# TODO(larryob): Don't install dev dependencies
RUN poetry install --no-root

FROM base AS runtime

# Set working directory
WORKDIR /app

# Copy venv
COPY --from=python-deps /venv /venv
ENV PATH="/venv/bin:${PATH}"

# Expose port 8000
EXPOSE 8000

# Run the application
ENTRYPOINT ["python", "-m" "apis.alpine_web_api.main"]