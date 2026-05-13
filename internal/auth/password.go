package auth

import (
	"errors"
	"fmt"

	"golang.org/x/crypto/bcrypt"
)

const minimumPasswordLength = 12

var ErrPasswordTooShort = errors.New("password must be at least 12 characters")

func HashPassword(password string) (string, error) {
	if len(password) < minimumPasswordLength {
		return "", ErrPasswordTooShort
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", fmt.Errorf("hash password: %w", err)
	}
	return string(hash), nil
}

func CheckPassword(hash, password string) bool {
	if hash == "" || password == "" {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}
