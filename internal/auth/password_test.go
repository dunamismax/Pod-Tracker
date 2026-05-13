package auth

import (
	"errors"
	"testing"
)

func TestHashPasswordRejectsShortPasswords(t *testing.T) {
	_, err := HashPassword("too-short")
	if !errors.Is(err, ErrPasswordTooShort) {
		t.Fatalf("expected ErrPasswordTooShort, got %v", err)
	}
}

func TestHashPasswordAndCheckPassword(t *testing.T) {
	hash, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatalf("hash password: %v", err)
	}

	if hash == "correct horse battery staple" {
		t.Fatalf("hash stored the raw password")
	}
	if !CheckPassword(hash, "correct horse battery staple") {
		t.Fatalf("password did not verify")
	}
	if CheckPassword(hash, "wrong horse battery staple") {
		t.Fatalf("wrong password verified")
	}
}
