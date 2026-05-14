package httpserver

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
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
	addressVisibility := r.FormValue("address_visibility")
	if addressVisibility == "" {
		addressVisibility = "rsvps"
	}

	if title == "" || startTimeStr == "" || visibility == "" {
		data.Error = "Title, start time, and visibility are required."
		s.render(w, r, http.StatusUnprocessableEntity, "event_new.html", data)
		return
	}
	if !validEventVisibility(visibility) || !validAddressVisibility(addressVisibility) {
		data.Error = "Choose a valid event and address visibility."
		s.render(w, r, http.StatusUnprocessableEntity, "event_new.html", data)
		return
	}

	startTime, err := time.Parse("2006-01-02T15:04", startTimeStr)
	if err != nil {
		data.Error = "Invalid start time format."
		s.render(w, r, http.StatusUnprocessableEntity, "event_new.html", data)
		return
	}

	var location *CreateEventLocationParams
	locationName := strings.TrimSpace(r.FormValue("location_name"))
	if locationName != "" {
		location = &CreateEventLocationParams{
			Name:          locationName,
			AddressLine1:  strings.TrimSpace(r.FormValue("address_line1")),
			AddressLine2:  strings.TrimSpace(r.FormValue("address_line2")),
			City:          strings.TrimSpace(r.FormValue("city")),
			StateProvince: strings.TrimSpace(r.FormValue("state_province")),
			PostalCode:    strings.TrimSpace(r.FormValue("postal_code")),
			Country:       strings.TrimSpace(r.FormValue("country")),
			Notes:         strings.TrimSpace(r.FormValue("location_notes")),
		}
	}

	inviteToken, err := newPublicToken()
	if err != nil {
		s.logger.Error("create event token", "err", err, "request_id", RequestID(r.Context()))
		http.Error(w, "failed to create event", http.StatusInternalServerError)
		return
	}

	event, err := s.store.CreateEvent(r.Context(), CreateEventParams{
		PlaygroupID:       playgroup.ID,
		Title:             title,
		Description:       description,
		StartTime:         startTime,
		Visibility:        visibility,
		InviteToken:       inviteToken,
		Location:          location,
		AddressVisibility: addressVisibility,
		CreatedBy:         user.ID,
	})
	if err != nil {
		s.logger.Error("create event", "err", err, "request_id", RequestID(r.Context()))
		http.Error(w, "failed to create event", http.StatusInternalServerError)
		return
	}

	http.Redirect(w, r, "/events/"+uuidText(event.ID), http.StatusSeeOther)
}

func (s *Server) eventView(w http.ResponseWriter, r *http.Request) {
	if !s.requireUser(w, r) {
		return
	}

	user, _ := CurrentUser(r.Context())

	idStr := r.PathValue("id")
	var id pgtype.UUID
	if err := id.Scan(idStr); err != nil {
		http.NotFound(w, r)
		return
	}

	event, err := s.store.GetEventForUser(r.Context(), id, user.ID)
	if err != nil {
		http.NotFound(w, r)
		return
	}

	rsvps, err := s.store.ListEventRSVPs(r.Context(), id)
	if err != nil {
		s.logger.Error("list event rsvps", "err", err, "request_id", RequestID(r.Context()))
	}

	var userRSVP *EventRSVP
	for _, rsvp := range rsvps {
		if rsvp.UserID == user.ID {
			userRSVP = &rsvp
			break
		}
	}

	data := s.newTemplateData(w, r)
	data.Event = &event
	data.RSVPs = rsvps
	data.UserRSVP = userRSVP
	if event.Visibility == "public_safe" {
		data.PublicEventURL = "/e/" + event.InviteToken
	}
	data.CanEditEvent = canManageEvent(event.MemberRole)
	if location, ok := s.eventLocation(r, event.ID); ok {
		data.EventLocation = &location
	}
	data.ShowEventAddress = s.canShowEventAddress(r, event, user.ID, userRSVP, false)

	s.render(w, r, http.StatusOK, "event_view.html", data)
}

func (s *Server) rsvpEvent(w http.ResponseWriter, r *http.Request) {
	if !s.requireUser(w, r) {
		return
	}

	user, _ := CurrentUser(r.Context())

	idStr := r.PathValue("id")
	var id pgtype.UUID
	if err := id.Scan(idStr); err != nil {
		http.NotFound(w, r)
		return
	}

	status := strings.TrimSpace(r.FormValue("status"))
	if status != "yes" && status != "maybe" && status != "no" && status != "waitlist" {
		http.Error(w, "invalid status", http.StatusBadRequest)
		return
	}

	notes := strings.TrimSpace(r.FormValue("notes"))

	event, err := s.store.GetEventForUser(r.Context(), id, user.ID)
	if err != nil {
		http.NotFound(w, r)
		return
	}

	existing, err := s.store.GetEventRSVP(r.Context(), event.ID, user.ID)
	if err == nil {
		_, err = s.store.UpdateEventRSVP(r.Context(), UpdateEventRSVPParams{
			ID:     existing.ID,
			Status: status,
			Notes:  notes,
		})
	} else {
		_, err = s.store.CreateEventRSVP(r.Context(), CreateEventRSVPParams{
			EventID: event.ID,
			UserID:  user.ID,
			Status:  status,
			Notes:   notes,
		})
	}

	if err != nil {
		s.logger.Error("save event rsvp", "err", err, "request_id", RequestID(r.Context()))
		http.Error(w, "failed to save rsvp", http.StatusInternalServerError)
		return
	}

	http.Redirect(w, r, "/events/"+idStr, http.StatusSeeOther)
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

	user, _ := CurrentUser(r.Context())
	event, err := s.store.GetEventForUser(r.Context(), id, user.ID)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	if !canManageEvent(event.MemberRole) {
		http.Error(w, "forbidden", http.StatusForbidden)
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

	user, _ := CurrentUser(r.Context())
	event, err := s.store.GetEventForUser(r.Context(), id, user.ID)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	if !canManageEvent(event.MemberRole) {
		http.Error(w, "forbidden", http.StatusForbidden)
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

	http.Redirect(w, r, "/events/"+uuidText(updatedEvent.ID), http.StatusSeeOther)
}

func (s *Server) publicEventView(w http.ResponseWriter, r *http.Request) {
	event, err := s.store.GetEventByToken(r.Context(), strings.TrimSpace(r.PathValue("token")))
	if err != nil || event.Visibility != "public_safe" {
		http.NotFound(w, r)
		return
	}

	data := s.newTemplateData(w, r)
	data.Event = &event
	if location, ok := s.eventLocation(r, event.ID); ok {
		data.EventLocation = &location
	}
	data.ShowEventAddress = s.canShowEventAddress(r, event, pgtype.UUID{}, nil, true)
	s.render(w, r, http.StatusOK, "event_public.html", data)
}

func (s *Server) guestRSVPForm(w http.ResponseWriter, r *http.Request) {
	event, err := s.store.GetEventByToken(r.Context(), strings.TrimSpace(r.PathValue("token")))
	if err != nil {
		http.NotFound(w, r)
		return
	}
	data := s.newTemplateData(w, r)
	data.Event = &event
	if location, ok := s.eventLocation(r, event.ID); ok {
		data.EventLocation = &location
	}
	data.ShowEventAddress = s.canShowEventAddress(r, event, pgtype.UUID{}, nil, true)
	s.render(w, r, http.StatusOK, "event_guest_rsvp.html", data)
}

func (s *Server) guestRSVP(w http.ResponseWriter, r *http.Request) {
	token := strings.TrimSpace(r.PathValue("token"))
	event, err := s.store.GetEventByToken(r.Context(), token)
	if err != nil {
		http.NotFound(w, r)
		return
	}

	guestName := strings.TrimSpace(r.FormValue("guest_name"))
	status := strings.TrimSpace(r.FormValue("status"))
	notes := strings.TrimSpace(r.FormValue("notes"))
	if guestName == "" || (status != "yes" && status != "maybe" && status != "no" && status != "waitlist") {
		data := s.newTemplateData(w, r)
		data.Event = &event
		data.Error = "Name and a valid RSVP status are required."
		if location, ok := s.eventLocation(r, event.ID); ok {
			data.EventLocation = &location
		}
		data.ShowEventAddress = s.canShowEventAddress(r, event, pgtype.UUID{}, nil, true)
		s.render(w, r, http.StatusUnprocessableEntity, "event_guest_rsvp.html", data)
		return
	}

	if _, err := s.store.CreateEventRSVP(r.Context(), CreateEventRSVPParams{
		EventID:   event.ID,
		GuestName: &guestName,
		Status:    status,
		Notes:     notes,
	}); err != nil {
		s.logger.Error("save guest rsvp", "err", err, "request_id", RequestID(r.Context()))
		http.Error(w, "failed to save rsvp", http.StatusInternalServerError)
		return
	}
	http.Redirect(w, r, "/rsvp/"+token+"?saved=1", http.StatusSeeOther)
}

func (s *Server) calendarFeed(w http.ResponseWriter, r *http.Request) {
	if !s.requireUser(w, r) {
		return
	}
	user, _ := CurrentUser(r.Context())
	playgroups, err := s.store.ListPlaygroupsForUser(r.Context(), user.ID)
	if err != nil {
		s.logger.Error("calendar playgroups", "err", err, "request_id", RequestID(r.Context()))
		http.Error(w, "calendar failed", http.StatusInternalServerError)
		return
	}

	var builder strings.Builder
	builder.WriteString("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Pod Tracker//Events//EN\r\nCALSCALE:GREGORIAN\r\n")
	for _, playgroup := range playgroups {
		events, err := s.store.ListEventsForPlaygroup(r.Context(), playgroup.ID)
		if err != nil {
			s.logger.Warn("calendar events", "playgroup", playgroup.Slug, "err", err, "request_id", RequestID(r.Context()))
			continue
		}
		for _, event := range events {
			id, _ := event.ID.Value()
			builder.WriteString("BEGIN:VEVENT\r\n")
			builder.WriteString("UID:" + icsEscape(fmt.Sprintf("%v@pod-tracker.app", id)) + "\r\n")
			builder.WriteString("DTSTAMP:" + time.Now().UTC().Format("20060102T150405Z") + "\r\n")
			builder.WriteString("DTSTART:" + event.StartTime.UTC().Format("20060102T150405Z") + "\r\n")
			if event.EndTime != nil {
				builder.WriteString("DTEND:" + event.EndTime.UTC().Format("20060102T150405Z") + "\r\n")
			}
			builder.WriteString("SUMMARY:" + icsEscape(event.Title) + "\r\n")
			if event.Description != "" {
				builder.WriteString("DESCRIPTION:" + icsEscape(event.Description) + "\r\n")
			}
			if location, ok := s.eventLocationByID(r, event.ID); ok {
				builder.WriteString("LOCATION:" + icsEscape(location.Name) + "\r\n")
			}
			builder.WriteString("END:VEVENT\r\n")
		}
	}
	builder.WriteString("END:VCALENDAR\r\n")

	w.Header().Set("Content-Type", "text/calendar; charset=utf-8")
	w.Header().Set("Content-Disposition", `inline; filename="pod-tracker.ics"`)
	_, _ = w.Write([]byte(builder.String()))
}

func (s *Server) eventLocation(r *http.Request, eventID pgtype.UUID) (EventLocation, bool) {
	if !eventID.Valid {
		return EventLocation{}, false
	}
	return s.eventLocationByID(r, eventID)
}

func (s *Server) eventLocationByID(r *http.Request, eventID pgtype.UUID) (EventLocation, bool) {
	location, err := s.store.GetEventLocationForEvent(r.Context(), eventID)
	if err != nil {
		if !errors.Is(err, pgx.ErrNoRows) {
			s.logger.Warn("get event location", "err", err, "request_id", RequestID(r.Context()))
		}
		return EventLocation{}, false
	}
	return location, true
}

func (s *Server) canShowEventAddress(r *http.Request, event Event, userID pgtype.UUID, userRSVP *EventRSVP, guestScope bool) bool {
	hosts, err := s.store.ListEventHosts(r.Context(), event.ID)
	if err != nil {
		s.logger.Warn("list event hosts", "err", err, "request_id", RequestID(r.Context()))
		return false
	}
	visibility := "hidden"
	for _, host := range hosts {
		if userID.Valid && host.UserID == userID {
			return true
		}
		if host.AddressVisibility == "public" {
			visibility = "public"
		} else if visibility != "public" && host.AddressVisibility == "members" {
			visibility = "members"
		} else if visibility != "public" && visibility != "members" && host.AddressVisibility == "rsvps" {
			visibility = "rsvps"
		}
	}
	if guestScope {
		return visibility == "public"
	}
	if event.MemberRole == "owner" || event.MemberRole == "admin" || event.MemberRole == "host" {
		return true
	}
	switch visibility {
	case "public", "members":
		return true
	case "rsvps":
		return userRSVP != nil && (userRSVP.Status == "yes" || userRSVP.Status == "maybe" || userRSVP.Status == "waitlist")
	default:
		return false
	}
}

func validEventVisibility(value string) bool {
	return value == "members" || value == "invite_only" || value == "public_safe"
}

func validAddressVisibility(value string) bool {
	return value == "rsvps" || value == "members" || value == "public" || value == "hidden"
}

func canManageEvent(role string) bool {
	return role == "owner" || role == "admin" || role == "host"
}

func newPublicToken() (string, error) {
	var token [24]byte
	if _, err := rand.Read(token[:]); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(token[:]), nil
}

func icsEscape(value string) string {
	value = strings.ReplaceAll(value, `\`, `\\`)
	value = strings.ReplaceAll(value, ";", `\;`)
	value = strings.ReplaceAll(value, ",", `\,`)
	value = strings.ReplaceAll(value, "\r\n", `\n`)
	value = strings.ReplaceAll(value, "\n", `\n`)
	return value
}

func uuidText(id pgtype.UUID) string {
	value, err := id.Value()
	if err != nil || value == nil {
		return ""
	}
	if text, ok := value.(string); ok {
		return text
	}
	return fmt.Sprint(value)
}
