"""
Единый экземпляр SlowAPI Limiter: подключается в main как app.state.limiter.
Роутеры импортируют limiter отсюда — лимиты корректно применяются.
"""

from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)
