from django.db import models
from django.db.models.functions import Lower, Trim


class Pod(models.Model):
    name = models.CharField(max_length=120, db_index=True)
    description = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["name"]
        constraints = [
            models.UniqueConstraint(
                Lower(Trim("name")),
                name="pods_pod_name_ci_unique",
            )
        ]

    def __str__(self) -> str:
        return self.name


class Event(models.Model):
    pod = models.ForeignKey(Pod, on_delete=models.CASCADE, related_name="events")
    title = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    location = models.CharField(max_length=255, blank=True)
    scheduled_for = models.DateTimeField(db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["scheduled_for", "title"]

    def __str__(self) -> str:
        return f"{self.title} ({self.pod.name})"
