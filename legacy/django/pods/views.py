from datetime import timedelta

from django.contrib import messages
from django.db.models import Count
from django.http import HttpRequest, HttpResponse
from django.shortcuts import redirect, render
from django.utils import timezone
from django.views.decorators.http import require_GET, require_POST

from .forms import EventForm, PodForm
from .models import Event, Pod


def render_dashboard(
    request: HttpRequest,
    *,
    pod_form: PodForm | None = None,
    event_form: EventForm | None = None,
    status: int = 200,
) -> HttpResponse:
    now = timezone.now()
    pods = Pod.objects.annotate(event_count=Count("events")).order_by("name")
    events = Event.objects.select_related("pod").filter(
        scheduled_for__gte=now - timedelta(days=1)
    )
    context = {
        "pod_form": pod_form or PodForm(),
        "event_form": event_form or EventForm(),
        "pods": pods,
        "events": events[:20],
        "summary": {
            "pod_count": pods.count(),
            "event_count": Event.objects.count(),
            "upcoming_count": Event.objects.filter(scheduled_for__gte=now).count(),
        },
    }
    return render(request, "pods/dashboard.html", context, status=status)


@require_GET
def dashboard(request: HttpRequest) -> HttpResponse:
    return render_dashboard(request)


@require_POST
def create_pod(request: HttpRequest) -> HttpResponse:
    form = PodForm(request.POST)
    if form.is_valid():
        pod = form.save()
        messages.success(request, f'Created pod "{pod.name}".')
        return redirect("pods:dashboard")
    return render_dashboard(request, pod_form=form, status=400)


@require_POST
def create_event(request: HttpRequest) -> HttpResponse:
    form = EventForm(request.POST)
    if form.is_valid():
        event = form.save()
        messages.success(request, f'Scheduled "{event.title}" for {event.pod.name}.')
        return redirect("pods:dashboard")
    return render_dashboard(request, event_form=form, status=400)
