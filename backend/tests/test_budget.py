def create_group_and_subcategory(client, headers, group_name="Еда", subcategory_name="Продукты"):
    group_resp = client.post("/budget/groups", json={
        "name": group_name,
        "type": "expense"
    }, headers=headers)
    assert group_resp.status_code in [200, 201]
    group_id = group_resp.json()["id"]

    sub_resp = client.post("/budget/subcategories", json={
        "name": subcategory_name,
        "group_id": group_id
    }, headers=headers)
    assert sub_resp.status_code in [200, 201]
    return group_resp.json(), sub_resp.json()


def test_create_group_and_subcategory(client, test_user):
    token = test_user["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    group, sub = create_group_and_subcategory(client, headers, group_name="Еда", subcategory_name="Продукты")
    assert group["name"] == "Еда"
    assert sub["name"] == "Продукты"
    assert sub["group_id"] == group["id"]

def test_create_transaction(client, test_user):
    token = test_user["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    _, sub = create_group_and_subcategory(client, headers, group_name="Тест", subcategory_name="Подкатегория")
    cat_id = sub["id"]

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
    token = test_user["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    
    response = client.get("/budget/transactions", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert "items" in data
    assert "has_more" in data
    assert "total" in data
    assert isinstance(data["items"], list)

def test_delete_transaction(client, test_user):
    token = test_user["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    _, sub = create_group_and_subcategory(client, headers, group_name="DelCat", subcategory_name="DelSub")
    cat_id = sub["id"]

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
        trans = client.get("/budget/transactions", headers=headers).json()["items"]
        # Ищем нашу транзакцию по описанию, если ID нет в ответе
        for t in trans:
            if t.get("description") == "ToDelete":
                tr_id = t["id"]
                break
    
    assert tr_id is not None
    
    del_resp = client.delete(f"/budget/transactions/{tr_id}", headers=headers)
    assert del_resp.status_code == 200


def test_budget_export_excel_with_date_filters(client, test_user):
    token = test_user["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    _, sub = create_group_and_subcategory(client, headers, group_name="Экспорт", subcategory_name="Фильтр")

    tx_resp = client.post("/budget/transactions", json={
        "amount": 123.45,
        "category_id": sub["id"],
        "description": "Экспортная транзакция",
        "date": "2026-04-10T12:00:00",
        "transaction_type": "expense"
    }, headers=headers)
    assert tx_resp.status_code in [200, 201]

    export_resp = client.get(
        "/budget/export/excel?start_date=2026-04-01T00:00:00&end_date=2026-04-30T23:59:59",
        headers=headers
    )
    assert export_resp.status_code == 200
    assert "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" in export_resp.headers.get("content-type", "")
    assert "attachment; filename=budget_export_" in export_resp.headers.get("content-disposition", "")