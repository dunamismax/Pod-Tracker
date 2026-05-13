package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
)

const SessionCookieName = "pod_tracker_session"

func NewSessionToken() (string, []byte, error) {
	var token [32]byte
	if _, err := rand.Read(token[:]); err != nil {
		return "", nil, fmt.Errorf("generate session token: %w", err)
	}

	encoded := base64.RawURLEncoding.EncodeToString(token[:])
	hash := sha256.Sum256(token[:])
	return encoded, hash[:], nil
}

func HashSessionToken(encoded string) ([]byte, error) {
	token, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil {
		return nil, fmt.Errorf("decode session token: %w", err)
	}
	if len(token) != 32 {
		return nil, fmt.Errorf("decode session token: unexpected token length %d", len(token))
	}

	hash := sha256.Sum256(token)
	return hash[:], nil
}
