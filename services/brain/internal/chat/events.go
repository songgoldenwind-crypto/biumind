// Cross-device sync events (transactional outbox).
//
// Every chat write other devices must observe inserts a brain.events
// row IN THE SAME TRANSACTION as the business write — the same outbox
// pattern as wiki (internal/wiki/store). The brain_events LISTEN
// trigger + events.Listener/poller forward the row to the realtime
// service, which fans out per topic (= scope).
//
// Scope convention: chat:user:<user_id> — three-part colon form
// (dot-form topics fail topic parsing → 403, see the aigc precedent).
// Subscribe-side authz is Cedar self-only (policies.cedar system 节:
// resource.kind == "chat:user" && resource.id == principal.id).
//
// Privacy: threads with sync_enabled=false NEVER emit — their content
// must not travel any server-side channel (§3.5.3 toggle).
package chat

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// Event types written to brain.events.event_type.
const (
	EventMessageCreated = "chat.message_created"
	EventThreadUpdated  = "chat.thread_updated"
	EventThreadDeleted  = "chat.thread_deleted"
	EventMessageDeleted = "chat.message_deleted"
	// WorkBuddy 遥控：等审批 / 任务结束，打到 chat:user:<id> 让手机补状态。
	EventTaskAttention = "chat.task_attention"
	EventTaskCompleted = "chat.task_completed"
	EventTaskFailed    = "chat.task_failed"
	EventTaskStarted   = "chat.task_started"
)

// emitEvent inserts a brain.events row inside tx. Mirrors wiki
// store's emitEvent; kept chat-local so each domain owns its scope.
// Payloads carry ids only — never message content.
func emitEvent(ctx context.Context, tx pgx.Tx, userID uuid.UUID,
	eventType string, payload map[string]any,
) error {
	pl, _ := json.Marshal(payload)
	scope := fmt.Sprintf("chat:user:%s", userID)
	_, err := tx.Exec(ctx, `
		INSERT INTO brain.events (scope, actor_type, actor_id, event_type, payload)
		VALUES ($1, 'user', $2, $3, $4)
	`, scope, userID.String(), eventType, pl)
	return err
}

// EmitUserEvent 在 chat 写事务之外插一条 brain.events。Agent Plane 旁路
// 审批/完成帧时用。thread 不存在或 sync_enabled=false 时静默跳过。
func (s *Store) EmitUserEvent(ctx context.Context, userID, threadID uuid.UUID,
	eventType string, payload map[string]any,
) error {
	if s == nil || userID == uuid.Nil || threadID == uuid.Nil || eventType == "" {
		return nil
	}
	var syncEnabled bool
	err := s.pool.QueryRow(ctx,
		`SELECT sync_enabled FROM chat.threads WHERE id = $1 AND user_id = $2`,
		threadID, userID).Scan(&syncEnabled)
	if err != nil || !syncEnabled {
		return nil
	}
	pl, _ := json.Marshal(payload)
	scope := fmt.Sprintf("chat:user:%s", userID)
	_, err = s.pool.Exec(ctx, `
		INSERT INTO brain.events (scope, actor_type, actor_id, event_type, payload)
		VALUES ($1, 'user', $2, $3, $4)
	`, scope, userID.String(), eventType, pl)
	return err
}

// RecordTaskLifecycle writes metadata.task.status and emits chat.task_*
// plus chat.thread_updated so other devices refresh list chips. sync_enabled=false
// threads are skipped (same privacy gate as EmitUserEvent).
func (s *Store) RecordTaskLifecycle(ctx context.Context, userID, threadID uuid.UUID,
	eventType string, payload map[string]any,
) error {
	if s == nil || userID == uuid.Nil || threadID == uuid.Nil || eventType == "" {
		return nil
	}
	status, ok := StatusFromEvent(eventType)
	if !ok {
		return s.EmitUserEvent(ctx, userID, threadID, eventType, payload)
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var metadata []byte
	var syncEnabled bool
	err = tx.QueryRow(ctx,
		`SELECT metadata, sync_enabled FROM chat.threads WHERE id = $1 AND user_id = $2 FOR UPDATE`,
		threadID, userID).Scan(&metadata, &syncEnabled)
	if err != nil || !syncEnabled {
		return nil
	}
	if eventType == EventTaskStarted && ShouldSkipStarted(ParseThreadTask(metadata).Status) {
		return nil
	}
	patched, err := PatchTaskStatus(metadata, status)
	if err != nil {
		return err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE chat.threads SET metadata = $3, updated_at = now() WHERE id = $1 AND user_id = $2`,
		threadID, userID, patched); err != nil {
		return err
	}
	if payload == nil {
		payload = map[string]any{}
	}
	if _, has := payload["thread_id"]; !has {
		payload["thread_id"] = threadID.String()
	}
	if err := emitEvent(ctx, tx, userID, eventType, payload); err != nil {
		return err
	}
	if err := emitEvent(ctx, tx, userID, EventThreadUpdated, map[string]any{
		"thread_id": threadID.String(),
	}); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// RecordTaskArtifacts merges deliverable pointers into metadata.task.artifacts.
func (s *Store) RecordTaskArtifacts(ctx context.Context, userID, threadID uuid.UUID, items []TaskArtifactMeta) error {
	if s == nil || userID == uuid.Nil || threadID == uuid.Nil || len(items) == 0 {
		return nil
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var metadata []byte
	var syncEnabled bool
	err = tx.QueryRow(ctx,
		`SELECT metadata, sync_enabled FROM chat.threads WHERE id = $1 AND user_id = $2 FOR UPDATE`,
		threadID, userID).Scan(&metadata, &syncEnabled)
	if err != nil {
		return nil
	}
	patched, err := MergeTaskArtifacts(metadata, items)
	if err != nil {
		return err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE chat.threads SET metadata = $3, updated_at = now() WHERE id = $1 AND user_id = $2`,
		threadID, userID, patched); err != nil {
		return err
	}
	if syncEnabled {
		if err := emitEvent(ctx, tx, userID, EventThreadUpdated, map[string]any{
			"thread_id": threadID.String(),
		}); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// RecordTaskMeta writes kind / run_style into metadata.task without
// dropping status or artifacts. Missing thread is a no-op (local-first
// create happens before EnsureThread).
func (s *Store) RecordTaskMeta(ctx context.Context, userID, threadID uuid.UUID, kind, runStyle string) error {
	if s == nil || userID == uuid.Nil || threadID == uuid.Nil || (kind == "" && runStyle == "") {
		return nil
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var metadata []byte
	var syncEnabled bool
	err = tx.QueryRow(ctx,
		`SELECT metadata, sync_enabled FROM chat.threads WHERE id = $1 AND user_id = $2 FOR UPDATE`,
		threadID, userID).Scan(&metadata, &syncEnabled)
	if err != nil {
		return nil
	}
	patched, err := PatchTaskFields(metadata, kind, runStyle)
	if err != nil {
		return err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE chat.threads SET metadata = $3, updated_at = now() WHERE id = $1 AND user_id = $2`,
		threadID, userID, patched); err != nil {
		return err
	}
	if syncEnabled {
		if err := emitEvent(ctx, tx, userID, EventThreadUpdated, map[string]any{
			"thread_id": threadID.String(),
		}); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// terminalStatus reports whether a message status is a final,
// user-visible state. Mid-stream states (pending/processing/
// streaming) stay silent on the bus — the terminal INSERT/UPDATE is
// what other devices sync from.
func terminalStatus(s string) bool {
	switch s {
	case StatusSuccess, StatusError, StatusPaused:
		return true
	}
	return false
}

// emitMessageCreatedTx writes the chat.message_created outbox row for
// a message that just became visible to other devices: a terminal-
// status user/assistant row. tool/system roles and mid-stream
// placeholders stay silent (the terminal UPDATE announces those).
// sync_enabled=false threads never emit.
func emitMessageCreatedTx(ctx context.Context, tx pgx.Tx, m *Message) error {
	if m.Role != RoleUser && m.Role != RoleAssistant {
		return nil
	}
	if !terminalStatus(m.Status) {
		return nil
	}
	var syncEnabled bool
	if err := tx.QueryRow(ctx,
		`SELECT sync_enabled FROM chat.threads WHERE id = $1`,
		m.ThreadID).Scan(&syncEnabled); err != nil {
		return err
	}
	if !syncEnabled {
		return nil
	}
	return emitEvent(ctx, tx, m.UserID, EventMessageCreated, map[string]any{
		"thread_id":  m.ThreadID.String(),
		"message_id": m.ID.String(),
		"position":   m.Position,
		"role":       m.Role,
	})
}
