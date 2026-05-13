package httpserver

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"net/http"
)

const (
	csrfCookieName = "pod_tracker_csrf"
	csrfFormField  = "csrf_token"
	csrfPurpose    = "pod-tracker-csrf-v1"
)

func (s *Server) csrfProtection(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !requiresCSRF(r.Method) {
			next.ServeHTTP(w, r)
			return
		}

		cookie, err := r.Cookie(csrfCookieName)
		if err != nil || cookie.Value == "" {
			http.Error(w, "invalid csrf token", http.StatusForbidden)
			return
		}
		if err := r.ParseForm(); err != nil {
			http.Error(w, "invalid form", http.StatusBadRequest)
			return
		}

		expected := csrfToken(cookie.Value)
		actual := r.Form.Get(csrfFormField)
		if !hmac.Equal([]byte(expected), []byte(actual)) {
			http.Error(w, "invalid csrf token", http.StatusForbidden)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func requiresCSRF(method string) bool {
	switch method {
	case http.MethodPost, http.MethodPut, http.MethodPatch, http.MethodDelete:
		return true
	default:
		return false
	}
}

func (s *Server) csrfToken(w http.ResponseWriter, r *http.Request) string {
	seed := ""
	if cookie, err := r.Cookie(csrfCookieName); err == nil {
		seed = cookie.Value
	}
	if !validCSRFSeed(seed) {
		seed = newCSRFSeed()
		http.SetCookie(w, &http.Cookie{
			Name:     csrfCookieName,
			Value:    seed,
			Path:     "/",
			HttpOnly: true,
			Secure:   s.secureCookies(),
			SameSite: http.SameSiteLaxMode,
			MaxAge:   60 * 60 * 24,
		})
	}
	return csrfToken(seed)
}

func csrfToken(seed string) string {
	mac := hmac.New(sha256.New, []byte(seed))
	_, _ = mac.Write([]byte(csrfPurpose))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func newCSRFSeed() string {
	var seed [32]byte
	if _, err := rand.Read(seed[:]); err != nil {
		return ""
	}
	return base64.RawURLEncoding.EncodeToString(seed[:])
}

func validCSRFSeed(seed string) bool {
	decoded, err := base64.RawURLEncoding.DecodeString(seed)
	return err == nil && len(decoded) == 32
}
