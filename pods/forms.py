from django import forms
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from .models import Event, Pod


class PodForm(forms.ModelForm):
    class Meta:
        model = Pod
        fields = ["name", "description"]
        widgets = {
            "name": forms.TextInput(
                attrs={
                    "placeholder": "Friday Pod",
                }
            ),
            "description": forms.Textarea(
                attrs={
                    "rows": 4,
                    "placeholder": "Small recurring group with a standing time and place.",
                }
            ),
        }

    def clean_name(self) -> str:
        name = self.cleaned_data["name"].strip()
        existing_pods = Pod.objects.filter(name__iexact=name)

        if self.instance.pk:
            existing_pods = existing_pods.exclude(pk=self.instance.pk)

        if existing_pods.exists():
            raise forms.ValidationError("A pod with this name already exists.")

        return name


class EventForm(forms.ModelForm):
    timezone = forms.CharField(required=False, widget=forms.HiddenInput())
    scheduled_for = forms.DateTimeField(
        input_formats=["%Y-%m-%dT%H:%M"],
        widget=forms.DateTimeInput(attrs={"type": "datetime-local"}),
        help_text="Uses your browser's local timezone.",
    )

    class Meta:
        model = Event
        fields = ["pod", "title", "location", "scheduled_for", "description"]
        widgets = {
            "title": forms.TextInput(
                attrs={
                    "placeholder": "Commander Night",
                }
            ),
            "location": forms.TextInput(
                attrs={
                    "placeholder": "Library meeting room",
                }
            ),
            "description": forms.Textarea(
                attrs={
                    "rows": 4,
                    "placeholder": "Optional notes, agenda, or what to bring.",
                }
            ),
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["pod"].queryset = Pod.objects.order_by("name")
        self.fields["pod"].empty_label = "Select a pod"

    def clean_timezone(self) -> str:
        timezone_name = self.cleaned_data["timezone"].strip()
        if not timezone_name:
            return ""

        try:
            ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError as exc:
            raise forms.ValidationError("Submit a valid timezone.") from exc

        return timezone_name
