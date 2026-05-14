package email

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

type Client struct {
	apiKey string
	sender string
	http   *http.Client
}

func NewClient(apiKey, sender string) *Client {
	return &Client{
		apiKey: apiKey,
		sender: sender,
		http: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

type smtp2goPayload struct {
	APIKey string      `json:"api_key"`
	To     []string    `json:"to"`
	Sender string      `json:"sender"`
	Subject string     `json:"subject"`
	TextBody string    `json:"text_body"`
	HTMLBody string    `json:"html_body,omitempty"`
}

func (c *Client) Send(ctx context.Context, to, subject, textBody, htmlBody string) error {
	if c.apiKey == "" {
		return fmt.Errorf("smtp2go api key not configured")
	}

	payload := smtp2goPayload{
		APIKey:   c.apiKey,
		To:       []string{to},
		Sender:   c.sender,
		Subject:  subject,
		TextBody: textBody,
		HTMLBody: htmlBody,
	}

	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal payload: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api.smtp2go.com/v3/email/send", bytes.NewReader(bodyBytes))
	if err != nil {
		return fmt.Errorf("new request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		var errResp map[string]interface{}
		_ = json.NewDecoder(resp.Body).Decode(&errResp)
		return fmt.Errorf("smtp2go error (status %d): %v", resp.StatusCode, errResp)
	}

	return nil
}
