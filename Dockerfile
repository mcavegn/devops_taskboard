# Multi-stage build: the builder stage installs dependencies, the runtime image
# carries neither pip cache nor compilers. Result: a smaller image and less
# attack surface.

# Basis Stufe ---
# Basis-Image: slim bedeutet abgespeckte debian mit python, version 3.12, nicht latest, Stufe base darauf wird gebaut
FROM python:3.12-slim AS base
# python legt kein .pyc an, was in kurzlebigen Containern keinen Sinn machen würde
# python puffert stdout / stderr nicht, Logs erscheinen sofort. nötig für docker & gunicorn echtzeit logs
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
# Arbeitsverzeichnis ist /app
WORKDIR /app

# Builder Stufe ---
# darf chaotisch sein (compiler, caches, zwischendateien)
# baut auf base auf -> erbt ENV und WORKDIR
# kopiert reqs
# installiert diese, no-cache verhindert dass pip downloads cache in layer landet,
# --prefix instaliert alles in separaten Verzeichnis
FROM base AS builder
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Laufzeit Stufe ---
# saubere runtime stufe (kopiert nur endergebnis von builder)
# frischer Aufbau von base, alles was in builder an Zwischenwerkzeug entstand bleibt draussen
# legt unpriviligierten Nutzer appuser an, mit hoher, fester UID 10001
# --create-home gibt user ein home Verzeichnis, darum never run as root
# Standardmässig läuft der Prozess im Container als root. Das ist gefährlich
FROM base AS runtime
# Never run containers as root: a process escape would otherwise be root inside
# the container, which is uncomfortably close to root on the host.
RUN useradd --create-home --uid 10001 appuser

# holt in builder Stufe installierte Pakete aus /installnach /usr/local
COPY --from=builder /install /usr/local
# Anwendungscode kopieren und Besitzer auf appuser setzen
COPY --chown=appuser:appuser app/ ./app/
COPY --chown=appuser:appuser wsgi.py ./
# reqs VOR app weil reqs ändert selten, das kann immer übernommen werden, app ändert ständig
# docker verwirft ab erster Änderung history und buat neu, pip install muss somit nicht jedes mal gemacht werden

# ab hier läuft alles als appuser
# Container lauscht auf Port 8000 (hier als Dokumentation und Hinweis für Werkzeuge)
# erst mit docker run .... -p 8000:8000 wird Container-Prot geöffnet und von aussen erreicht (http://localhost:8000)
# Syntax ist -p <Wirt-Port>:<Container-Port>
USER appuser
EXPOSE 8000

# Standardwert wenn kein --build-arg übergeben wird
ARG APP_VERSION=0.0.0-dev
ENV APP_VERSION=${APP_VERSION}

# One worker by default. The in-memory repository (used when DATABASE_URL is
# unset) is per-process, so a second worker would serve a second, different
# task list. Once DATABASE_URL points at Postgres the state is shared and you
# should raise this — docker-compose.yml sets GUNICORN_WORKERS=2.
ENV GUNICORN_WORKERS=1
# beim setzen von 2, ohne postgres, würde ein worker den einen Teil der Tasks halten der andere die anderen
# ENV und nicht ARG, weil es zur Laufzeit (CMD) gelesen wird

# Docker prüft regelmässig ob Container gesund ist
# nutzt urllib von python, weil curl nicht im slim image existiert
# trifft /helath, nicht /ready weil langsame Datenbank würde es als ungesund markieren
# intervall, alle 30s prüfen
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import sys,urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status == 200 else 1)"

# sh -c so ${GUNICORN_WORKERS} expands; exec so gunicorn becomes PID 1 and
# receives SIGTERM directly (graceful shutdown on `docker stop`).
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:8000 --workers ${GUNICORN_WORKERS} --access-logfile - wsgi:app"]
# Shell-Wrapper-Form (siehe CMD vs. ENTRYPOINT) expandiert Variablen, macht gunicorn zu PID 1
# gunicorn, Produktionstauglicher WSGI-Server, nicht Flask Entwicklungsserver
# --bind 0.0.0.0:8000 lauscht auf allen Netzwerkschnittstellen -> nur so ist Container von aussern via -p8000:8000 erreichbar
# --Workers = Anzahl Arbeitsprozesse (default 1 aus ENV oben) postgres hebt es auf 2
# --access-logfile schreibt es in stdout wo docker logs einsammelt
# wsgi:app -> das Modul heisst wsgi, Objekt ist app