package httpserver

import (
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

func (s *Server) newEventForm(w http.ResponseWriter, r *http.Request) {
	if !s.requireUser(w, r) {
		return
	}

	slug := r.PathValue("slug")
	user, _ := CurrentUser(r.Context())

	playgroup, err := s.store.GetPlaygroupBySlugAndUser(r.Context(), slug, user.ID)
	if err != nil {
		s.logger.Error("get playgroup for new event", "err", err, "request_id", RequestID(r.Context()))
		http.NotFound(w, r)
		return
	}

	data := s.newTemplateData(w, r)
	data.Playgroup = &playgroup
	s.render(w, r, http.StatusOK, "event_new.html", data)
}

func (s *Server) createEvent(w http.ResponseWriter, r *http.Request) {
	if !s.requireUser(w, r) {
		return
	}

	slug := r.PathValue("slug")
	user, _ := CurrentUser(r.Context())

	playgroup, err := s.store.GetPlaygroupBySlugAndUser(r.Context(), slug, user.ID)
	if err != nil {
		http.NotFound(w, r)
		return
	}

	data := s.newTemplateData(w, r)
	data.Playgroup = &playgroup

	title := strings.TrimSpace(r.FormValue("title"))
	description := strings.TrimSpace(r.FormValue("description"))
	startTimeStr := r.FormValue("start_time")
	visibility := r.FormValue("visibility")

	if title == "" || startTimeStr == "" || visibility == "" {
		data.Error = "Title, start time, and visibility are required."
		s.render(w, r, http.StatusUnprocessableEntity, "event_new.html", data)
		return
	}

	startTime, err := time.Parse("2006-01-02T15:04", startTimeStr)
	if err != nil {
		data.Error = "Invalid start time format."
		s.render(w, r, http.StatusUnprocessableEntity, "event_new.html", data)
		return
	}

	event, err := s.store.CreateEvent(r.Context(), CreateEventParams{
		PlaygroupID: playgroup.ID,
		Title:       title,
		Description: description,
		StartTime:   startTime,
		Visibility:  visibility,
		CreatedBy:   user.ID,
	})
	if err != nil {
		s.logger.Error("create event", "err", err, "request_id", RequestID(r.Context()))
		http.Error(w, "failed to create event", http.StatusInternalServerError)
		return
	}

	// Wait, the id is a pgtype.UUID. We need to format it to redirect to /events/{id}
	var idStr string
	if b, err := event.ID.Value(); err == nil && b != nil {
		idStr = b.(string)
	}

	http.Redirect(w, r, "/events/"+idStr, http.StatusSeeOther)
}

func (s *Server) eventView(w http.ResponseWriter, r *http.Request) {
	if !s.requireUser(w, r) {
		return
	}

	idStr := r.PathValue("id")
	var id pgtype.UUID
	if err := id.Scan(idStr); err != nil {
		http.NotFound(w, r)
		return
	}

	event, err := s.store.GetEventByID(r.Context(), id)
	if err != nil {
		http.NotFound(w, r)
		return
	}

	data := s.newTemplateData(w, r)
	data.Event = &event
	s.render(w, r, http.StatusOK, "event_view.html", data)
}

func (s *Server) editEventForm(w http.ResponseWriter, r *http.Request) {
	if !s.requireUser(w, r) {
		return
	}

	idStr := r.PathValue("id")
	var id pgtype.UUID
	if err := id.Scan(idStr); err != nil {
		http.NotFound(w, r)
		return
	}

	event, err := s.store.GetEventByID(r.Context(), id)
	if err != nil {
		http.NotFound(w, r)
		return
	}

	data := s.newTemplateData(w, r)
	data.Event = &event
	s.render(w, r, http.StatusOK, "event_edit.html", data)
}

func (s *Server) updateEvent(w http.ResponseWriter, r *http.Request) {
	if !s.requireUser(w, r) {
		return
	}

	idStr := r.PathValue("id")
	var id pgtype.UUID
	if err := id.Scan(idStr); err != nil {
		http.NotFound(w, r)
		return
	}

	event, err := s.store.GetEventByID(r.Context(), id)
	if err != nil {
		http.NotFound(w, r)
		return
	}

	data := s.newTemplateData(w, r)
	data.Event = &event

	title := strings.TrimSpace(r.FormValue("title"))
	description := strings.TrimSpace(r.FormValue("description"))
	startTimeStr := r.FormValue("start_time")
	visibility := r.FormValue("visibility")

	if title == "" || startTimeStr == "" || visibility == "" {
		data.Error = "Title, start time, and visibility are required."
		s.render(w, r, http.StatusUnprocessableEntity, "event_edit.html", data)
		return
	}

	startTime, err := time.Parse("2006-01-02T15:04", startTimeStr)
	if err != nil {
		data.Error = "Invalid start time format."
		s.render(w, r, http.StatusUnprocessableEntity, "event_edit.html", data)
		return
	}

	updatedEvent, err := s.store.UpdateEvent(r.Context(), UpdateEventParams{
		ID:          event.ID,
		Title:       title,
		Description: description,
		StartTime:   startTime,
		Visibility:  visibility,
	})
	if err != nil {
		s.logger.Error("update event", "err", err, "request_id", RequestID(r.Context()))
		http.Error(w, "failed to update event", http.StatusInternalServerError)
		return
	}

	var updatedIDStr string
	if b, err := updatedEvent.ID.Value(); err == nil && b != nil {
		updatedIDStr = b.(string)
	}

	http.Redirect(w, r, "/events/"+updatedIDStr, http.StatusSeeOther)
}

