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

type PGStore struct {
	pool *pgxpool.Pool
}

func NewPGStore(pool *pgxpool.Pool) *PGStore {
	return &PGStore{pool: pool}
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
