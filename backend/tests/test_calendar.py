def get_token(client, name):
    resp = client.post("/auth/login", json={"name": name})
    return resp.json()["access_token"]

def test_create_event(client, test_user):
    token = get_token(client, test_user["name"])
    headers = {"Authorization": f"Bearer {token}"}
    
    response = client.post("/calendar/events", json={
        "title": "День рождения",
        "event_date": "2023-11-20T10:00:00",  # Исправленное имя поля и формат
        "description": "Праздник"
    }, headers=headers)
    
    if response.status_code == 422:
        print(f"Event creation error: {response.json()}")
    
    assert response.status_code in [200, 201]
    assert response.json()["title"] == "День рождения"

def test_get_events(client, test_user):
    token = get_token(client, test_user["name"])
    headers = {"Authorization": f"Bearer {token}"}
    
    response = client.get("/calendar/events", headers=headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)

def test_delete_event(client, test_user):
    token = get_token(client, test_user["name"])
    headers = {"Authorization": f"Bearer {token}"}
    
    ev_resp = client.post("/calendar/events", json={
        "title": "ToDelete", 
        "event_date": "2023-12-01T10:00:00",
        "description": "To be deleted"
    }, headers=headers)
    
    ev_id = ev_resp.json().get("id")
    if not ev_id:
        events = client.get("/calendar/events", headers=headers).json()
        for e in events:
            if e.get("title") == "ToDelete":
                ev_id = e["id"]
                break
    
    assert ev_id is not None
    
    del_resp = client.delete(f"/calendar/events/{ev_id}", headers=headers)
    assert del_resp.status_code == 200