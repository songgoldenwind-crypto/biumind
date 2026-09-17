// TaskAttentionObserver —— Queue.PublishSessionFrame 旁路，把「等审批 /
// 任务结束」写成 brain.events，Realtime 扇出到 chat:user:<id>，手机遥控
// 不必挂着同一条 WS 也能看到角标。
//
// 热路径纪律同 ElicitationObserver：非目标帧零 DB；目标帧写失败只 Warn。

package agentplane

import (
	"context"
	"encoding/json"
	"log/slog"
	"strings"

	sdkproto "github.com/biumind/biumind/packages/go-sdk/biu/sdkproto/v1"
	chatpkg "github.com/biumind/biumind/services/brain/internal/chat"
	"github.com/google/uuid"
)

type taskEventEmitter interface {
	RecordTaskLifecycle(ctx context.Context, userID, threadID uuid.UUID, eventType string, payload map[string]any) error
}

type sessionByID interface {
	GetSessionByID(ctx context.Context, sessionID uuid.UUID) (*Session, error)
}

// TaskAttentionObserver 把审批/完成帧落到 chat:user 总线。
type TaskAttentionObserver struct {
	store  sessionByID
	chat   taskEventEmitter
	logger *slog.Logger
}

func NewTaskAttentionObserver(store sessionByID, chat taskEventEmitter, logger *slog.Logger) *TaskAttentionObserver {
	if logger == nil {
		logger = slog.Default()
	}
	return &TaskAttentionObserver{store: store, chat: chat, logger: logger}
}

type taskFramePeek struct {
	Type    string `json:"type"`
	Subtype string `json:"subtype"`
	IsError bool   `json:"is_error"`
	Request *struct {
		Subtype  string `json:"subtype"`
		ToolName string `json:"tool_name"`
	} `json:"request"`
}

// ClassifyTaskFrame 纯函数：控制帧 / result 帧 → 事件类型。单测不碰 DB。
func ClassifyTaskFrame(payload []byte) (eventType, reason string, ok bool) {
	var f taskFramePeek
	if err := json.Unmarshal(payload, &f); err != nil {
		return "", "", false
	}
	switch f.Type {
	case sdkproto.TypeControlRequest:
		if f.Request == nil {
			return "", "", false
		}
		switch f.Request.Subtype {
		case sdkproto.SubtypeCanUseTool:
			return chatpkg.EventTaskAttention, "approval", true
		case sdkproto.SubtypeElicitation:
			return chatpkg.EventTaskAttention, "elicitation", true
		}
	case sdkproto.TypeResult:
		if f.IsError || strings.HasPrefix(f.Subtype, "error") {
			return chatpkg.EventTaskFailed, "error", true
		}
		return chatpkg.EventTaskCompleted, "success", true
	}
	return "", "", false
}

func taskFrameToolName(payload []byte) string {
	var f taskFramePeek
	if err := json.Unmarshal(payload, &f); err != nil || f.Request == nil {
		return ""
	}
	return strings.TrimSpace(f.Request.ToolName)
}

func (o *TaskAttentionObserver) ObserveFrame(ctx context.Context, sessionID uuid.UUID, payload []byte) {
	if o == nil || o.store == nil || o.chat == nil {
		return
	}
	eventType, reason, ok := ClassifyTaskFrame(payload)
	if !ok {
		return
	}
	sess, err := o.store.GetSessionByID(ctx, sessionID)
	if err != nil || sess == nil || sess.ThreadID == nil || *sess.ThreadID == uuid.Nil {
		return
	}
	pl := map[string]any{
		"thread_id":  sess.ThreadID.String(),
		"session_id": sessionID.String(),
		"reason":     reason,
	}
	if tool := taskFrameToolName(payload); tool != "" {
		pl["tool_name"] = tool
	}
	if err := o.chat.RecordTaskLifecycle(ctx, sess.UserID, *sess.ThreadID, eventType, pl); err != nil {
		o.logger.Warn("task attention observer: emit failed",
			"session_id", sessionID, "event", eventType, "err", err)
	}
}

// recordTaskStarted emits chat.task_started after a session is actually
// running a turn. No-ops when ChatStore or thread is missing.
func (s *Server) recordTaskStarted(ctx context.Context, userID uuid.UUID, sess *Session) {
	if s == nil || sess == nil || s.ChatStore == nil || sess.ThreadID == nil || *sess.ThreadID == uuid.Nil {
		return
	}
	pl := map[string]any{
		"thread_id":  sess.ThreadID.String(),
		"session_id": sess.SessionID.String(),
		"reason":     "turn",
	}
	if err := s.ChatStore.RecordTaskLifecycle(ctx, userID, *sess.ThreadID, chatpkg.EventTaskStarted, pl); err != nil {
		if s.Logger != nil {
			s.Logger.Warn("agentplane: task_started emit failed",
				"session_id", sess.SessionID, "err", err)
		}
	}
}
