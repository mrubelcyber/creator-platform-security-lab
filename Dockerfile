FROM python:3.14-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY backend ./backend

# Create a dedicated non-root application user
RUN useradd --create-home --shell /usr/sbin/nologin appuser \
    && mkdir -p /app/database /app/logs \
    && chown -R appuser:appuser /app

ENV PYTHONUNBUFFERED=1

EXPOSE 5000

# Run the application with least privilege
USER appuser

CMD ["python", "-m", "backend.app"]
