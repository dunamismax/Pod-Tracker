package httpserver

import (
	"net/http"
	"regexp"
	"strings"
)

var slugUnsafe = regexp.MustCompile(`[^a-z0-9]+`)

func (s *Server) dashboard(w http.ResponseWriter, r *http.Request) {
	if !s.requireUser(w, r) {
		return
	}

	data := s.newTemplateData(w, r)
	if s.store != nil {
		user, _ := CurrentUser(r.Context())
		playgroups, err := s.store.ListPlaygroupsForUser(r.Context(), user.ID)
		if err != nil {
			s.logger.Error("list dashboard playgroups", "err", err, "request_id", RequestID(r.Context()))
			http.Error(w, "dashboard failed", http.StatusInternalServerError)
			return
		}
		data.Playgroups = playgroups
	}
	s.render(w, r, http.StatusOK, "dashboard.html", data)
}

func (s *Server) playgroups(w http.ResponseWriter, r *http.Request) {
	if !s.requireUser(w, r) {
		return
	}

	data := s.newTemplateData(w, r)
	if s.store != nil {
		user, _ := CurrentUser(r.Context())
		playgroups, err := s.store.ListPlaygroupsForUser(r.Context(), user.ID)
		if err != nil {
			s.logger.Error("list playgroups", "err", err, "request_id", RequestID(r.Context()))
			http.Error(w, "playgroups failed", http.StatusInternalServerError)
			return
		}
		data.Playgroups = playgroups
	}
	s.render(w, r, http.StatusOK, "playgroups.html", data)
}

func (s *Server) createPlaygroup(w http.ResponseWriter, r *http.Request) {
	if !s.requireUser(w, r) {
		return
	}
	if s.store == nil {
		http.Error(w, "database is not configured", http.StatusServiceUnavailable)
		return
	}

	data := s.newTemplateData(w, r)
	name := strings.TrimSpace(r.FormValue("name"))
	description := strings.TrimSpace(r.FormValue("description"))
	data.PlaygroupName = name
	data.PlaygroupDescription = description
	if name == "" {
		data.Error = "Playgroup name is required."
		s.render(w, r, http.StatusUnprocessableEntity, "playgroups.html", data)
		return
	}

	slug := slugify(name)
	if slug == "" {
		data.Error = "Playgroup name must include at least one letter or number."
		s.render(w, r, http.StatusUnprocessableEntity, "playgroups.html", data)
		return
	}

	user, _ := CurrentUser(r.Context())
	if _, err := s.store.CreatePlaygroup(r.Context(), CreatePlaygroupParams{
		OwnerID:     user.ID,
		Name:        name,
		Slug:        slug,
		Description: description,
	}); err != nil {
		if isUniqueViolation(err) {
			data.Error = "A playgroup already uses that slug. Adjust the name and try again."
			s.render(w, r, http.StatusUnprocessableEntity, "playgroups.html", data)
			return
		}
		s.logger.Error("create playgroup", "err", err, "request_id", RequestID(r.Context()))
		http.Error(w, "playgroup creation failed", http.StatusInternalServerError)
		return
	}

	http.Redirect(w, r, "/playgroups", http.StatusSeeOther)
}

func slugify(value string) string {
	slug := strings.ToLower(strings.TrimSpace(value))
	slug = slugUnsafe.ReplaceAllString(slug, "-")
	slug = strings.Trim(slug, "-")
	for strings.Contains(slug, "--") {
		slug = strings.ReplaceAll(slug, "--", "-")
	}
	return slug
}
