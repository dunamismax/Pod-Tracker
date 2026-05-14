package config

import "os"

type Config struct {
	Addr          string
	DatabaseURL   string
	Environment   string
	StaticDir     string
	TemplateDir   string
	SMTP2GOAPIKey string
	SMTPSender    string
}

func Load() Config {
	return Config{
		Addr:          env("POD_TRACKER_ADDR", ":8080"),
		DatabaseURL:   os.Getenv("POD_TRACKER_DATABASE_URL"),
		Environment:   env("POD_TRACKER_ENV", "development"),
		StaticDir:     env("POD_TRACKER_STATIC_DIR", "web/static"),
		TemplateDir:   env("POD_TRACKER_TEMPLATE_DIR", "web/templates"),
		SMTP2GOAPIKey: os.Getenv("POD_TRACKER_SMTP2GO_API_KEY"),
		SMTPSender:    env("POD_TRACKER_SMTP_SENDER", "pod-tracker@pod-tracker.app"),
	}
}

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
