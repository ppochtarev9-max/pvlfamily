def get_token(client, name):
    resp = client.post("/auth/login", json={"name": name})
    return resp.json()["access_token"]

def test_create_category(client, test_user):
    token = get_token(client, test_user["name"])
    headers = {"Authorization": f"Bearer {token}"}
    
    response = client.post("/budget/categories", json={
        "name": "Еда",
        "type": "expense"
    }, headers=headers)
    assert response.status_code in [200, 201]
    assert response.json()["name"] == "Еда"

def test_create_transaction(client, test_user):
    token = get_token(client, test_user["name"])
    headers = {"Authorization": f"Bearer {token}"}
    
    # Создаем категорию
    cat_resp = client.post("/budget/categories", json={"name": "Тест", "type": "expense"}, headers=headers)
    assert cat_resp.status_code in [200, 201]
    cat_data = cat_resp.json()
    cat_id = cat_data.get("id")
    
    # Если ID нет в ответе, берем из списка
    if not cat_id:
        cats = client.get("/budget/categories", headers=headers).json()
        cat_id = cats[-1]["id"] if cats else None
    
    assert cat_id is not None

    # Исправленный запрос транзакции
    response = client.post("/budget/transactions", json={
        "amount": 100.50,
        "category_id": cat_id,
        "description": "Тестовая покупка",
        "date": "2023-10-01T12:00:00",  # ISO формат
        "transaction_type": "expense"   # Обязательное поле
    }, headers=headers)
    
    if response.status_code != 200:
        print(f"Transaction error details: {response.json()}")
        
    assert response.status_code in [200, 201]
    assert response.json()["amount"] == 100.50

def test_get_transactions(client, test_user):
    token = get_token(client, test_user["name"])
    headers = {"Authorization": f"Bearer {token}"}
    
    response = client.get("/budget/transactions", headers=headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)

def test_delete_transaction(client, test_user):
    token = get_token(client, test_user["name"])
    headers = {"Authorization": f"Bearer {token}"}
    
    # Создаем категорию
    cat_resp = client.post("/budget/categories", json={"name": "DelCat", "type": "expense"}, headers=headers)
    cat_id = cat_resp.json().get("id")
    if not cat_id:
        cats = client.get("/budget/categories", headers=headers).json()
        cat_id = cats[-1]["id"]

    # Создаем транзакцию
    tr_resp = client.post("/budget/transactions", json={
        "amount": 50, 
        "category_id": cat_id, 
        "description": "ToDelete", 
        "date": "2023-10-01T12:00:00",
        "transaction_type": "expense"
    }, headers=headers)
    
    tr_id = tr_resp.json().get("id")
    if not tr_id:
        trans = client.get("/budget/transactions", headers=headers).json()
        # Ищем нашу транзакцию по описанию, если ID нет в ответе
        for t in trans:
            if t.get("description") == "ToDelete":
                tr_id = t["id"]
                break
    
    assert tr_id is not None
    
    del_resp = client.delete(f"/budget/transactions/{tr_id}", headers=headers)
    assert del_resp.status_code == 200