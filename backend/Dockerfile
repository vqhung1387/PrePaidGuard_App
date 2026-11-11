FROM python:3.12-slim AS build
WORKDIR /srv/backend
RUN pip install --no-cache-dir uv==0.13.7
COPY backend/pyproject.toml backend/uv.lock ./
RUN uv sync --locked --no-dev --no-install-project

FROM python:3.12-slim
WORKDIR /srv/backend
ENV PATH="/srv/backend/.venv/bin:${PATH}" PYTHONUNBUFFERED=1
COPY --from=build /srv/backend/.venv .venv
COPY backend/app app
COPY backend/migrations migrations
COPY backend/alembic.ini backend/start.sh ./
COPY shared /srv/shared
USER 10001
EXPOSE 8000
CMD ["sh", "./start.sh"]
