# Musterlösung – tests/test_stats.py
#
# Lauffähige pytest-Tests für den Endpunkt GET /api/tasks/stats.
# Sie nutzen die Fixture `client` aus der echten tests/conftest.py (dieselbe wie
# in tests/test_api.py) und laufen ohne Datenbank gegen das In-Memory-Repository.


def _create(client, title):
    return client.post("/api/tasks", json={"title": title}).get_json()


def test_stats_on_empty_board(client):
    body = client.get("/api/tasks/stats").get_json()
    assert body == {"total": 0, "done": 0, "open": 0}


def test_stats_counts_open_and_done(client):
    first = _create(client, "Kapitel lesen")
    _create(client, "Labor machen")
    _create(client, "Wheel bauen")
    client.put(f"/api/tasks/{first['id']}", json={"done": True})

    body = client.get("/api/tasks/stats").get_json()
    assert body == {"total": 3, "done": 1, "open": 2}


def test_stats_all_done(client):
    for title in ("A", "B"):
        created = _create(client, title)
        client.put(f"/api/tasks/{created['id']}", json={"done": True})

    body = client.get("/api/tasks/stats").get_json()
    assert body == {"total": 2, "done": 2, "open": 0}


def test_stats_endpoint_returns_200(client):
    assert client.get("/api/tasks/stats").status_code == 200
