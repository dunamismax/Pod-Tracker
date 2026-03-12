from django.urls import path

from . import views


app_name = "pods"

urlpatterns = [
    path("", views.dashboard, name="dashboard"),
    path("pods/create/", views.create_pod, name="create_pod"),
    path("events/create/", views.create_event, name="create_event"),
]
