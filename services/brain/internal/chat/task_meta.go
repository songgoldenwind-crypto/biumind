package chat

import (
	"encoding/json"
	"time"
)

// ThreadTask is the WorkBuddy slice stored under metadata.task.
// jsonb_set only this object so model_params and other keys stay intact.
type ThreadTask struct {
	Status    string             `json:"status,omitempty"`
	Kind      string             `json:"kind,omitempty"`
	RunStyle  string             `json:"run_style,omitempty"`
	UpdatedAt string             `json:"updated_at,omitempty"`
	Artifacts []TaskArtifactMeta `json:"artifacts,omitempty"`
}

// TaskArtifactMeta is a downloadable deliverable pointer (Brain Files).
type TaskArtifactMeta struct {
	FileID string `json:"file_id,omitempty"`
	Path   string `json:"path,omitempty"`
	Kind   string `json:"kind,omitempty"`
	Title  string `json:"title,omitempty"`
}

func (t ThreadTask) hasAny() bool {
	return t.Status != "" || t.Kind != "" || t.RunStyle != "" || len(t.Artifacts) > 0
}

// StatusFromEvent maps a chat.task_* event to metadata.task.status.
func StatusFromEvent(eventType string) (status string, ok bool) {
	switch eventType {
	case EventTaskStarted:
		return "running", true
	case EventTaskAttention:
		return "awaiting", true
	case EventTaskCompleted:
		return "completed", true
	case EventTaskFailed:
		return "failed", true
	default:
		return "", false
	}
}

// ShouldSkipStarted avoids flipping awaiting/running back to running
// when a second open/resume races the same turn.
func ShouldSkipStarted(current string) bool {
	return current == "running" || current == "awaiting"
}

// ParseThreadTask reads metadata.task; malformed / missing → zero value.
func ParseThreadTask(metadata []byte) ThreadTask {
	if len(metadata) == 0 {
		return ThreadTask{}
	}
	var meta struct {
		Task *ThreadTask `json:"task"`
	}
	if err := json.Unmarshal(metadata, &meta); err != nil || meta.Task == nil {
		return ThreadTask{}
	}
	return *meta.Task
}

// PatchTaskStatus sets metadata.task.status + updated_at without dropping
// sibling keys (artifacts / kind / run_style / model_params).
func PatchTaskStatus(metadata []byte, status string) ([]byte, error) {
	root := map[string]any{}
	if len(metadata) > 0 {
		if err := json.Unmarshal(metadata, &root); err != nil {
			root = map[string]any{}
		}
	}
	task, _ := root["task"].(map[string]any)
	if task == nil {
		task = map[string]any{}
	}
	task["status"] = status
	task["updated_at"] = time.Now().UTC().Format(time.RFC3339)
	root["task"] = task
	return json.Marshal(root)
}

// PatchTaskFields sets kind / run_style without dropping status or artifacts.
func PatchTaskFields(metadata []byte, kind, runStyle string) ([]byte, error) {
	root := map[string]any{}
	if len(metadata) > 0 {
		if err := json.Unmarshal(metadata, &root); err != nil {
			root = map[string]any{}
		}
	}
	task, _ := root["task"].(map[string]any)
	if task == nil {
		task = map[string]any{}
	}
	if kind != "" {
		task["kind"] = kind
	}
	if runStyle != "" {
		task["run_style"] = runStyle
	}
	task["updated_at"] = time.Now().UTC().Format(time.RFC3339)
	root["task"] = task
	return json.Marshal(root)
}

// MergeTaskArtifacts writes/replaces artifacts by path (empty path uses file_id).
func MergeTaskArtifacts(metadata []byte, items []TaskArtifactMeta) ([]byte, error) {
	root := map[string]any{}
	if len(metadata) > 0 {
		if err := json.Unmarshal(metadata, &root); err != nil {
			root = map[string]any{}
		}
	}
	task, _ := root["task"].(map[string]any)
	if task == nil {
		task = map[string]any{}
	}
	cur := ParseThreadTask(metadata).Artifacts
	byKey := map[string]TaskArtifactMeta{}
	order := make([]string, 0, len(cur)+len(items))
	keyOf := func(a TaskArtifactMeta) string {
		if a.Path != "" {
			return "p:" + a.Path
		}
		return "f:" + a.FileID
	}
	for _, a := range cur {
		k := keyOf(a)
		if _, ok := byKey[k]; !ok {
			order = append(order, k)
		}
		byKey[k] = a
	}
	for _, a := range items {
		k := keyOf(a)
		if _, ok := byKey[k]; !ok {
			order = append(order, k)
		}
		byKey[k] = a
	}
	out := make([]TaskArtifactMeta, 0, len(order))
	for _, k := range order {
		out = append(out, byKey[k])
	}
	raw, err := json.Marshal(out)
	if err != nil {
		return nil, err
	}
	var asAny []any
	if err := json.Unmarshal(raw, &asAny); err != nil {
		return nil, err
	}
	task["artifacts"] = asAny
	task["updated_at"] = time.Now().UTC().Format(time.RFC3339)
	root["task"] = task
	return json.Marshal(root)
}
