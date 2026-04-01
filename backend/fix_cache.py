import re

with open('app/budget.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Функция-обертка для добавления заголовков
wrapper_code = '''
from fastapi.responses import Response

def add_no_cache_headers(response: Response):
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
    return response
'''

# Вставляем импорты и хелпер после импортов
if 'add_no_cache_headers' not in content:
    # Находим последний import
    lines = content.split('\n')
    insert_idx = 0
    for i, line in enumerate(lines):
        if line.startswith('from .') or line.startswith('router ='):
            insert_idx = i
            break
    
    header_block = [
        "from fastapi.responses import Response",
        "",
        "def add_no_cache_headers(response: Response):",
        "    response.headers[\"Cache-Control\"] = \"no-store, no-cache, must-revalidate, max-age=0\"",
        "    response.headers[\"Pragma\"] = \"no-cache\"",
        "    response.headers[\"Expires\"] = \"0\"",
        "    return response",
        ""
    ]
    
    for i, h_line in enumerate(header_block):
        lines.insert(insert_idx + i, h_line)
    
    content = '\n'.join(lines)

# Применяем декоратор или вызов к функциям GET
# Ищем определения функций get_transactions и get_categories и добавляем обработку ответа
# Простой способ: найти return в этих функциях и обернуть его

# Для get_transactions
old_tx_return = "return [make_tx_resp(t) for t in txs]"
new_tx_return = """resp = [make_tx_resp(t) for t in txs]
    # Явно помечаем ответ как некэшируемый (если бы использовали Response напрямую)
    # Но в FastAPI проще добавить middleware или dependency. 
    # Сделаем через простой возврат списка, а заголовки добавим в main.py или здесь через Response"""
    
# Так как менять сигнатуры рискованно, давайте лучше добавим простой Middleware в main.py или зависимостью.
# Но самый надежный способ без ломки - изменить функцию создания ответа.

# Давайте попробуем другой подход: просто перепишем функции с явным Response
# Найдем функцию get_transactions целиком
pattern_get_tx = r'(@router\.get\("/transactions".*?def get_transactions\(.*?\):.*?)(return \[make_tx_resp\(t\) for t in txs\])'
replacement_get_tx = r'\1    from fastapi.responses import JSONResponse\n    import json\n    data = [make_tx_resp(t) for t in txs]\n    response = JSONResponse(content=data)\n    response.headers["Cache-Control"] = "no-store"\n    return response'

content = re.sub(pattern_get_tx, replacement_get_tx, content, flags=re.DOTALL)

# Найдем функцию get_categories
pattern_get_cat = r'(@router\.get\("/categories".*?def get_categories\(.*?\):.*?)(return db\.query\(models\.Category\)\.all\(\))'
replacement_get_cat = r'\1    from fastapi.responses import JSONResponse\n    data = db.query(models.Category).all()\n    response = JSONResponse(content=data)\n    response.headers["Cache-Control"] = "no-store"\n    return response'

content = re.sub(pattern_get_cat, replacement_get_cat, content, flags=re.DOTALL)

with open('app/budget.py', 'w', encoding='utf-8') as f:
    f.write(content)

print("✅ Заголовки запрета кэширования добавлены.")
