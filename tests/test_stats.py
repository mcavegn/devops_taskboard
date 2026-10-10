def test_stats_empty_board(client):
    """Empty board returns zeros for total, done, open."""
    response = client.get("/api/tasks/stats")
    assert response.status_code == 200
    body = response.get_json()
    assert body["total"] == 0
    assert body["done"] == 0
    assert body["open"] == 0


def test_stats_mixed(client):
    """Mixed tasks: some done, some open."""
    # Create 4 tasks
    t1 = client.post("/api/tasks", json={"title": "Task 1"}).get_json()
    client.post("/api/tasks", json={"title": "Task 2"}).get_json()
    t3 = client.post("/api/tasks", json={"title": "Task 3"}).get_json()
    client.post("/api/tasks", json={"title": "Task 4"}).get_json()

    # Mark 2 as done
    client.put(f"/api/tasks/{t1['id']}", json={"done": True})
    client.put(f"/api/tasks/{t3['id']}", json={"done": True})

    response = client.get("/api/tasks/stats")
    assert response.status_code == 200
    body = response.get_json()
    assert body["total"] == 4
    assert body["done"] == 2
    assert body["open"] == 2


def test_stats_all_done(client):
    """All tasks done: open is 0."""
    t1 = client.post("/api/tasks", json={"title": "Task 1"}).get_json()
    t2 = client.post("/api/tasks", json={"title": "Task 2"}).get_json()
    t3 = client.post("/api/tasks", json={"title": "Task 3"}).get_json()

    # Mark all as done
    client.put(f"/api/tasks/{t1['id']}", json={"done": True})
    client.put(f"/api/tasks/{t2['id']}", json={"done": True})
    client.put(f"/api/tasks/{t3['id']}", json={"done": True})

    response = client.get("/api/tasks/stats")
    assert response.status_code == 200
    body = response.get_json()
    assert body["total"] == 3
    assert body["done"] == 3
    assert body["open"] == 0
