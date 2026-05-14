package httpserver

import (
	"context"
	"fmt"
	"net/netip"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/dunamismax/pod-tracker/internal/db"
	"github.com/dunamismax/pod-tracker/internal/db/sqlc"
)

type Store interface {
	CreateUser(context.Context, CreateUserParams) (User, error)
	GetUserByEmail(context.Context, string) (UserWithPassword, error)
	GetUserByID(context.Context, pgtype.UUID) (User, error)
	CreateSession(context.Context, CreateSessionParams) error
	GetSessionByTokenHash(context.Context, []byte) (Session, error)
	RevokeSession(context.Context, []byte) error
	ListPlaygroupsForUser(context.Context, pgtype.UUID) ([]Playgroup, error)
	CreatePlaygroup(context.Context, CreatePlaygroupParams) (Playgroup, error)
	GetPlaygroupBySlugAndUser(context.Context, string, pgtype.UUID) (Playgroup, error)
	CreateEvent(context.Context, CreateEventParams) (Event, error)
	GetEventByID(context.Context, pgtype.UUID) (Event, error)
	ListEventsForPlaygroup(context.Context, pgtype.UUID) ([]Event, error)
	UpdateEvent(context.Context, UpdateEventParams) (Event, error)
	GetEventRSVP(context.Context, pgtype.UUID, pgtype.UUID) (EventRSVP, error)
	ListEventRSVPs(context.Context, pgtype.UUID) ([]EventRSVP, error)
	CreateEventRSVP(context.Context, CreateEventRSVPParams) (EventRSVP, error)
	UpdateEventRSVP(context.Context, UpdateEventRSVPParams) (EventRSVP, error)
	EnqueueEmailDelivery(context.Context, EnqueueEmailParams) error
}

type User struct {
	ID          pgtype.UUID
	Email       string
	DisplayName string
}

type UserWithPassword struct {
	User
	PasswordHash string
}

type Session struct {
	UserID pgtype.UUID
}

type CreateUserParams struct {
	Email        string
	DisplayName  string
	PasswordHash string
}

type CreateSessionParams struct {
	UserID    pgtype.UUID
	TokenHash []byte
	UserAgent string
	IPAddress *netip.Addr
	ExpiresAt time.Time
}

type Playgroup struct {
	ID          pgtype.UUID
	Name        string
	Slug        string
	Description string
	Role        string
}

type CreatePlaygroupParams struct {
	OwnerID     pgtype.UUID
	Name        string
	Slug        string
	Description string
}

type Event struct {
	ID          pgtype.UUID
	PlaygroupID pgtype.UUID
	Title       string
	Description string
	StartTime   time.Time
	EndTime     *time.Time
	Visibility  string
}

type CreateEventParams struct {
	PlaygroupID pgtype.UUID
	Title       string
	Description string
	StartTime   time.Time
	EndTime     *time.Time
	Visibility  string
	CreatedBy   pgtype.UUID
}

type UpdateEventParams struct {
	ID          pgtype.UUID
	Title       string
	Description string
	StartTime   time.Time
	EndTime     *time.Time
	Visibility  string
}

type EventRSVP struct {
	ID                  pgtype.UUID
	EventID             pgtype.UUID
	UserID              pgtype.UUID
	GuestName           *string
	Status              string
	ArrivalTime         *time.Time
	LeavingTime         *time.Time
	GuestCount          int32
	TravelBufferMinutes *int32
	Notes               string
}

type CreateEventRSVPParams struct {
	EventID             pgtype.UUID
	UserID              pgtype.UUID
	GuestName           *string
	Status              string
	ArrivalTime         *time.Time
	LeavingTime         *time.Time
	GuestCount          int32
	TravelBufferMinutes *int32
	Notes               string
}

type UpdateEventRSVPParams struct {
	ID                  pgtype.UUID
	Status              string
	ArrivalTime         *time.Time
	LeavingTime         *time.Time
	GuestCount          int32
	TravelBufferMinutes *int32
	Notes               string
}

type EnqueueEmailParams struct {
	ToAddress string
	Subject   string
	TextBody  string
	HTMLBody  string
}

type PGStore struct {
	pool *pgxpool.Pool
}

func NewPGStore(pool *pgxpool.Pool) *PGStore {
	return &PGStore{pool: pool}
}

func (s *PGStore) EnqueueEmailDelivery(ctx context.Context, params EnqueueEmailParams) error {
	return db.WithTx(ctx, s.pool, func(tx pgx.Tx) error {
		queries := dbsql.New(tx)
		delivery, err := queries.InsertEmailDelivery(ctx, dbsql.InsertEmailDeliveryParams{
			ToAddress: params.ToAddress,
			Subject:   params.Subject,
			BodyText:  pgtype.Text{String: params.TextBody, Valid: params.TextBody != ""},
			BodyHtml:  pgtype.Text{String: params.HTMLBody, Valid: params.HTMLBody != ""},
		})
		if err != nil {
			return err
		}

		// Enqueue the job.
		var payload []byte
		var idStr string
		if b, err := delivery.ID.Value(); err == nil && b != nil {
			idStr = b.(string)
		}
		payload = []byte(fmt.Sprintf(`{"email_delivery_id": "%s"}`, idStr))

		_, err = queries.InsertBackgroundJob(ctx, dbsql.InsertBackgroundJobParams{
			Queue:   "default",
			JobType: "send_email",
			Payload: payload,
			RunAt:   pgtype.Timestamptz{Time: time.Now(), Valid: true},
		})
		return err
	})
}

func (s *PGStore) CreateUser(ctx context.Context, params CreateUserParams) (User, error) {
	user, err := dbsql.New(s.pool).CreateUser(ctx, dbsql.CreateUserParams{
		Email:        params.Email,
		DisplayName:  params.DisplayName,
		PasswordHash: params.PasswordHash,
	})
	if err != nil {
		return User{}, err
	}
	return userFromSQL(user), nil
}

func (s *PGStore) GetUserByEmail(ctx context.Context, email string) (UserWithPassword, error) {
	user, err := dbsql.New(s.pool).GetUserByEmail(ctx, email)
	if err != nil {
		return UserWithPassword{}, err
	}
	return userWithPasswordFromSQL(user), nil
}

func (s *PGStore) GetUserByID(ctx context.Context, id pgtype.UUID) (User, error) {
	user, err := dbsql.New(s.pool).GetUserByID(ctx, id)
	if err != nil {
		return User{}, err
	}
	return userFromSQL(user), nil
}

func (s *PGStore) CreateSession(ctx context.Context, params CreateSessionParams) error {
	_, err := dbsql.New(s.pool).CreateSession(ctx, dbsql.CreateSessionParams{
		UserID:    params.UserID,
		TokenHash: params.TokenHash,
		UserAgent: pgtype.Text{String: params.UserAgent, Valid: params.UserAgent != ""},
		IpAddress: params.IPAddress,
		ExpiresAt: pgtype.Timestamptz{Time: params.ExpiresAt, Valid: true},
	})
	return err
}

func (s *PGStore) GetSessionByTokenHash(ctx context.Context, tokenHash []byte) (Session, error) {
	session, err := dbsql.New(s.pool).GetSessionByTokenHash(ctx, tokenHash)
	if err != nil {
		return Session{}, err
	}
	return Session{UserID: session.UserID}, nil
}

func (s *PGStore) RevokeSession(ctx context.Context, tokenHash []byte) error {
	return dbsql.New(s.pool).RevokeSession(ctx, tokenHash)
}

func (s *PGStore) ListPlaygroupsForUser(ctx context.Context, userID pgtype.UUID) ([]Playgroup, error) {
	rows, err := dbsql.New(s.pool).ListPlaygroupsForUser(ctx, userID)
	if err != nil {
		return nil, err
	}

	playgroups := make([]Playgroup, 0, len(rows))
	for _, row := range rows {
		playgroups = append(playgroups, Playgroup{
			ID:          row.ID,
			Name:        row.Name,
			Slug:        row.Slug,
			Description: row.Description,
			Role:        row.Role,
		})
	}
	return playgroups, nil
}

func (s *PGStore) CreatePlaygroup(ctx context.Context, params CreatePlaygroupParams) (Playgroup, error) {
	var playgroup Playgroup
	err := db.WithTx(ctx, s.pool, func(tx pgx.Tx) error {
		queries := dbsql.New(tx)
		created, err := queries.CreatePlaygroup(ctx, dbsql.CreatePlaygroupParams{
			Name:        params.Name,
			Slug:        params.Slug,
			Description: params.Description,
			CreatedBy:   params.OwnerID,
		})
		if err != nil {
			return fmt.Errorf("create playgroup: %w", err)
		}
		if err := queries.CreateDefaultPlaygroupSettings(ctx, created.ID); err != nil {
			return fmt.Errorf("create playgroup settings: %w", err)
		}
		if err := queries.CreatePlaygroupMembership(ctx, dbsql.CreatePlaygroupMembershipParams{
			PlaygroupID: created.ID,
			UserID:      params.OwnerID,
			Role:        "owner",
		}); err != nil {
			return fmt.Errorf("create owner membership: %w", err)
		}

		playgroup = Playgroup{
			ID:          created.ID,
			Name:        created.Name,
			Slug:        created.Slug,
			Description: created.Description,
			Role:        "owner",
		}
		return nil
	})
	if err != nil {
		return Playgroup{}, err
	}
	return playgroup, nil
}

func (s *PGStore) GetPlaygroupBySlugAndUser(ctx context.Context, slug string, userID pgtype.UUID) (Playgroup, error) {
	row, err := dbsql.New(s.pool).GetPlaygroupBySlugAndUser(ctx, dbsql.GetPlaygroupBySlugAndUserParams{
		Slug:   slug,
		UserID: userID,
	})
	if err != nil {
		return Playgroup{}, err
	}
	return Playgroup{
		ID:          row.ID,
		Name:        row.Name,
		Slug:        row.Slug,
		Description: row.Description,
		Role:        row.Role,
	}, nil
}

func (s *PGStore) CreateEvent(ctx context.Context, params CreateEventParams) (Event, error) {
	var endTime pgtype.Timestamptz
	if params.EndTime != nil {
		endTime = pgtype.Timestamptz{Time: *params.EndTime, Valid: true}
	}
	row, err := dbsql.New(s.pool).CreateEvent(ctx, dbsql.CreateEventParams{
		PlaygroupID: params.PlaygroupID,
		Title:       params.Title,
		Description: params.Description,
		StartTime:   pgtype.Timestamptz{Time: params.StartTime, Valid: true},
		EndTime:     endTime,
		Visibility:  params.Visibility,
		CreatedBy:   params.CreatedBy,
	})
	if err != nil {
		return Event{}, err
	}
	return eventFromSQL(row), nil
}

func (s *PGStore) GetEventByID(ctx context.Context, id pgtype.UUID) (Event, error) {
	row, err := dbsql.New(s.pool).GetEvent(ctx, id)
	if err != nil {
		return Event{}, err
	}
	return eventFromSQL(row), nil
}

func (s *PGStore) ListEventsForPlaygroup(ctx context.Context, playgroupID pgtype.UUID) ([]Event, error) {
	rows, err := dbsql.New(s.pool).ListEventsForPlaygroup(ctx, playgroupID)
	if err != nil {
		return nil, err
	}
	events := make([]Event, 0, len(rows))
	for _, row := range rows {
		events = append(events, eventFromSQL(row))
	}
	return events, nil
}

func (s *PGStore) UpdateEvent(ctx context.Context, params UpdateEventParams) (Event, error) {
	var endTime pgtype.Timestamptz
	if params.EndTime != nil {
		endTime = pgtype.Timestamptz{Time: *params.EndTime, Valid: true}
	}
	row, err := dbsql.New(s.pool).UpdateEvent(ctx, dbsql.UpdateEventParams{
		ID:          params.ID,
		Title:       params.Title,
		Description: params.Description,
		StartTime:   pgtype.Timestamptz{Time: params.StartTime, Valid: true},
		EndTime:     endTime,
		Visibility:  params.Visibility,
	})
	if err != nil {
		return Event{}, err
	}
	return eventFromSQL(row), nil
}

func (s *PGStore) GetEventRSVP(ctx context.Context, eventID pgtype.UUID, userID pgtype.UUID) (EventRSVP, error) {
	row, err := dbsql.New(s.pool).GetEventRSVP(ctx, dbsql.GetEventRSVPParams{
		EventID: eventID,
		UserID:  userID,
	})
	if err != nil {
		return EventRSVP{}, err
	}
	return eventRSVPFromSQL(row), nil
}

func (s *PGStore) ListEventRSVPs(ctx context.Context, eventID pgtype.UUID) ([]EventRSVP, error) {
	rows, err := dbsql.New(s.pool).ListEventRSVPs(ctx, eventID)
	if err != nil {
		return nil, err
	}
	rsvps := make([]EventRSVP, 0, len(rows))
	for _, row := range rows {
		rsvps = append(rsvps, eventRSVPFromSQL(row))
	}
	return rsvps, nil
}

func (s *PGStore) CreateEventRSVP(ctx context.Context, params CreateEventRSVPParams) (EventRSVP, error) {
	var arrivalTime, leavingTime pgtype.Timestamptz
	if params.ArrivalTime != nil {
		arrivalTime = pgtype.Timestamptz{Time: *params.ArrivalTime, Valid: true}
	}
	if params.LeavingTime != nil {
		leavingTime = pgtype.Timestamptz{Time: *params.LeavingTime, Valid: true}
	}
	var travelBuffer pgtype.Int4
	if params.TravelBufferMinutes != nil {
		travelBuffer = pgtype.Int4{Int32: *params.TravelBufferMinutes, Valid: true}
	}
	var guestName pgtype.Text
	if params.GuestName != nil {
		guestName = pgtype.Text{String: *params.GuestName, Valid: true}
	}

	row, err := dbsql.New(s.pool).CreateEventRSVP(ctx, dbsql.CreateEventRSVPParams{
		EventID:             params.EventID,
		UserID:              params.UserID,
		GuestName:           guestName,
		Status:              params.Status,
		ArrivalTime:         arrivalTime,
		LeavingTime:         leavingTime,
		GuestCount:          params.GuestCount,
		TravelBufferMinutes: travelBuffer,
		Notes:               params.Notes,
	})
	if err != nil {
		return EventRSVP{}, err
	}
	return eventRSVPFromSQL(row), nil
}

func (s *PGStore) UpdateEventRSVP(ctx context.Context, params UpdateEventRSVPParams) (EventRSVP, error) {
	var arrivalTime, leavingTime pgtype.Timestamptz
	if params.ArrivalTime != nil {
		arrivalTime = pgtype.Timestamptz{Time: *params.ArrivalTime, Valid: true}
	}
	if params.LeavingTime != nil {
		leavingTime = pgtype.Timestamptz{Time: *params.LeavingTime, Valid: true}
	}
	var travelBuffer pgtype.Int4
	if params.TravelBufferMinutes != nil {
		travelBuffer = pgtype.Int4{Int32: *params.TravelBufferMinutes, Valid: true}
	}

	row, err := dbsql.New(s.pool).UpdateEventRSVP(ctx, dbsql.UpdateEventRSVPParams{
		ID:                  params.ID,
		Status:              params.Status,
		ArrivalTime:         arrivalTime,
		LeavingTime:         leavingTime,
		GuestCount:          params.GuestCount,
		TravelBufferMinutes: travelBuffer,
		Notes:               params.Notes,
	})
	if err != nil {
		return EventRSVP{}, err
	}
	return eventRSVPFromSQL(row), nil
}

func eventRSVPFromSQL(row dbsql.CoreEventRsvp) EventRSVP {
	var arrivalTime, leavingTime *time.Time
	if row.ArrivalTime.Valid {
		t := row.ArrivalTime.Time
		arrivalTime = &t
	}
	if row.LeavingTime.Valid {
		t := row.LeavingTime.Time
		leavingTime = &t
	}
	var travelBuffer *int32
	if row.TravelBufferMinutes.Valid {
		tb := row.TravelBufferMinutes.Int32
		travelBuffer = &tb
	}
	var guestName *string
	if row.GuestName.Valid {
		gn := row.GuestName.String
		guestName = &gn
	}

	return EventRSVP{
		ID:                  row.ID,
		EventID:             row.EventID,
		UserID:              row.UserID,
		GuestName:           guestName,
		Status:              row.Status,
		ArrivalTime:         arrivalTime,
		LeavingTime:         leavingTime,
		GuestCount:          row.GuestCount,
		TravelBufferMinutes: travelBuffer,
		Notes:               row.Notes,
	}
	}

	func eventFromSQL(row dbsql.CoreEvent) Event {
	var endTime *time.Time
	if row.EndTime.Valid {
		t := row.EndTime.Time
		endTime = &t
	}
	return Event{
		ID:          row.ID,
		PlaygroupID: row.PlaygroupID,
		Title:       row.Title,
		Description: row.Description,
		StartTime:   row.StartTime.Time,
		EndTime:     endTime,
		Visibility:  row.Visibility,
	}
}

func userFromSQL(user dbsql.CoreUser) User {
	return User{
		ID:          user.ID,
		Email:       user.Email,
		DisplayName: user.DisplayName,
	}
}

func userWithPasswordFromSQL(user dbsql.CoreUser) UserWithPassword {
	return UserWithPassword{
		User:         userFromSQL(user),
		PasswordHash: user.PasswordHash,
	}
}
