package chat

import (
	"encoding/json"
	"testing"

	"github.com/google/uuid"
)

func TestStatusFromEvent(t *testing.T) {
	cases := []struct {
		event string
		want  string
		ok    bool
	}{
		{EventTaskStarted, "running", true},
		{EventTaskAttention, "awaiting", true},
		{EventTaskCompleted, "completed", true},
		{EventTaskFailed, "failed", true},
		{"chat.thread_updated", "", false},
	}
	for _, tc := range cases {
		got, ok := StatusFromEvent(tc.event)
		if ok != tc.ok || got != tc.want {
			t.Fatalf("%s: got (%q,%v) want (%q,%v)", tc.event, got, ok, tc.want, tc.ok)
		}
	}
}

func TestParseThreadTaskPreservesArtifacts(t *testing.T) {
	in := []byte(`{
		"model_params": {"max_tokens": 100},
		"task": {
			"status": "completed",
			"kind": "office",
			"run_style": "execute",
			"artifacts": [{"file_id": "f1", "path": "/tmp/week.md", "kind": "markdown", "title": "week.md"}]
		}
	}`)
	got := ParseThreadTask(in)
	if got.Status != "completed" || got.Kind != "office" || got.RunStyle != "execute" {
		t.Fatalf("fields: %+v", got)
	}
	if len(got.Artifacts) != 1 || got.Artifacts[0].FileID != "f1" {
		t.Fatalf("artifacts: %+v", got.Artifacts)
	}
}

func TestParseThreadTaskEmpty(t *testing.T) {
	if ParseThreadTask(nil).Status != "" {
		t.Fatal("nil metadata should be empty")
	}
	if ParseThreadTask([]byte(`{}`)).Status != "" {
		t.Fatal("empty object should be empty")
	}
	if ParseThreadTask([]byte(`{not json`)).Status != "" {
		t.Fatal("malformed should be empty")
	}
}

func TestShouldSkipStarted(t *testing.T) {
	if !ShouldSkipStarted("running") {
		t.Fatal("running should skip started")
	}
	if !ShouldSkipStarted("awaiting") {
		t.Fatal("awaiting should skip started")
	}
	for _, s := range []string{"", "queued", "completed", "failed"} {
		if ShouldSkipStarted(s) {
			t.Fatalf("%q must not skip started", s)
		}
	}
}

func TestPatchTaskStatusKeepsArtifacts(t *testing.T) {
	in := []byte(`{
		"model_params": {"max_tokens": 8},
		"task": {
			"status": "running",
			"kind": "office",
			"artifacts": [{"file_id": "f1", "path": "/a.md"}]
		}
	}`)
	out, err := PatchTaskStatus(in, "completed")
	if err != nil {
		t.Fatal(err)
	}
	got := ParseThreadTask(out)
	if got.Status != "completed" {
		t.Fatalf("status=%q", got.Status)
	}
	if got.Kind != "office" || len(got.Artifacts) != 1 || got.Artifacts[0].FileID != "f1" {
		t.Fatalf("lost sibling fields: %+v", got)
	}
	var meta map[string]any
	if err := json.Unmarshal(out, &meta); err != nil {
		t.Fatal(err)
	}
	mp, _ := meta["model_params"].(map[string]any)
	if mp["max_tokens"] != float64(8) {
		t.Fatalf("model_params clobbered: %+v", meta["model_params"])
	}
	if got.UpdatedAt == "" {
		t.Fatal("updated_at should be set")
	}
}

func TestMergeTaskArtifactsReplacesSamePath(t *testing.T) {
	in := []byte(`{"task":{"status":"completed","artifacts":[{"path":"/a.md","file_id":"old"}]}}`)
	out, err := MergeTaskArtifacts(in, []TaskArtifactMeta{
		{Path: "/a.md", FileID: "new", Kind: "markdown", Title: "a.md"},
		{Path: "/b.csv", FileID: "b1", Kind: "sheet"},
	})
	if err != nil {
		t.Fatal(err)
	}
	got := ParseThreadTask(out)
	if len(got.Artifacts) != 2 {
		t.Fatalf("len=%d %+v", len(got.Artifacts), got.Artifacts)
	}
	if got.Artifacts[0].FileID != "new" || got.Artifacts[0].Path != "/a.md" {
		t.Fatalf("replace: %+v", got.Artifacts[0])
	}
	if got.Artifacts[1].FileID != "b1" {
		t.Fatalf("append: %+v", got.Artifacts[1])
	}
}

func TestMergeTaskArtifactsKeepsStatus(t *testing.T) {
	in := []byte(`{"task":{"status":"completed","kind":"office","artifacts":[]}}`)
	out, err := MergeTaskArtifacts(in, []TaskArtifactMeta{{Path: "/a.md", FileID: "f"}})
	if err != nil {
		t.Fatal(err)
	}
	got := ParseThreadTask(out)
	if got.Status != "completed" || got.Kind != "office" {
		t.Fatalf("lifecycle clobbered: %+v", got)
	}
	if len(got.Artifacts) != 1 || got.Artifacts[0].FileID != "f" {
		t.Fatalf("artifacts: %+v", got.Artifacts)
	}
}

func TestPatchTaskFieldsKeepsStatusAndArtifacts(t *testing.T) {
	in := []byte(`{"model_params":{"max_tokens":3},"task":{"status":"queued","artifacts":[{"path":"/a.md"}]}}`)
	out, err := PatchTaskFields(in, "office", "plan_first")
	if err != nil {
		t.Fatal(err)
	}
	got := ParseThreadTask(out)
	if got.Kind != "office" || got.RunStyle != "plan_first" {
		t.Fatalf("%+v", got)
	}
	if got.Status != "queued" || len(got.Artifacts) != 1 {
		t.Fatalf("lost lifecycle: %+v", got)
	}
	var meta map[string]any
	if err := json.Unmarshal(out, &meta); err != nil {
		t.Fatal(err)
	}
	mp, _ := meta["model_params"].(map[string]any)
	if mp["max_tokens"] != float64(3) {
		t.Fatalf("model_params clobbered: %+v", meta["model_params"])
	}
}

func TestThreadOutIncludesTask(t *testing.T) {
	tid := uuid.MustParse("11111111-1111-1111-1111-111111111111")
	uid := uuid.MustParse("22222222-2222-2222-2222-222222222222")
	th := &Thread{
		ID:       tid,
		UserID:   uid,
		Title:    "week",
		Metadata: []byte(`{"task":{"status":"completed","kind":"office"}}`),
	}
	out := threadOut(th)
	task, ok := out["task"].(ThreadTask)
	if !ok {
		t.Fatalf("task type %T", out["task"])
	}
	if task.Status != "completed" || task.Kind != "office" {
		t.Fatalf("%+v", task)
	}
}
