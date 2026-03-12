import os

from django.core.asgi import get_asgi_application

from .env import load_dotenv

load_dotenv()
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "podwatch.settings")

application = get_asgi_application()
