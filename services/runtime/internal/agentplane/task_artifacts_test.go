package agentplane

import (
	"encoding/json"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/google/uuid"
)

func TestIsWriteLikeTool(t *testing.T) {
	for _, name := range []string{"Write", "write", "Edit", "MultiEdit", "NotebookEdit"} {
		if !isWriteLikeTool(name) {
			t.Fatalf("%s should be write-like", name)
		}
	}
	for _, name := range []string{"Read", "Glob", "Bash", "TodoWrite"} {
		if isWriteLikeTool(name) {
			t.Fatalf("%s should not be write-like", name)
		}
	}
}

func TestIsTempArtifactPath(t *testing.T) {
	if !isTempArtifactPath("/tmp/foo.md") {
		t.Fatal("/tmp should be temp")
	}
	if !isTempArtifactPath("/Users/me/.hidden.md") {
		t.Fatal("dotfile should be temp")
	}
	if isTempArtifactPath("/Users/me/week.md") {
		t.Fatal("week.md should not be temp")
	}
}

func TestPathInWorkdir(t *testing.T) {
	root := t.TempDir()
	inside := filepath.Join(root, "week.md")
	if !pathInWorkdir(inside, root) {
		t.Fatalf("%s should be in %s", inside, root)
	}
	if pathInWorkdir("/etc/passwd", root) {
		t.Fatal("escape should be rejected")
	}
	if runtime.GOOS != "windows" {
		if pathInWorkdir(root+"/../outside.md", root) {
			t.Fatal(".. escape should be rejected")
		}
	}
}

func TestNoteWriteCandidateUsesPathKey(t *testing.T) {
	root := t.TempDir()
	week := filepath.Join(root, "week.md")
	var cands []string
	cands = noteWriteCandidate(cands, "write", map[string]any{"path": week}, root, false)
	if len(cands) != 1 || cands[0] != week {
		t.Fatalf("cands=%v", cands)
	}
}

func TestTrackWriteStartAndResult(t *testing.T) {
	root := t.TempDir()
	week := filepath.Join(root, "week.md")
	pending := map[string]string{}
	trackWriteStart(pending, "write", "tu1", map[string]any{"path": week}, root)
	if pending["tu1"] != week {
		t.Fatalf("pending=%v", pending)
	}
	cands := trackWriteResult(pending, nil, "tu1", false, root)
	if len(cands) != 1 || cands[0] != week {
		t.Fatalf("cands=%v", cands)
	}
}

func TestWorkPayloadUnmarshalUserBearerAndWorkdir(t *testing.T) {
	sid := uuid.New()
	uid := uuid.New()
	raw := []byte(`{
		"session_id":"` + sid.String() + `",
		"user_id":"` + uid.String() + `",
		"mode":"task",
		"prompt":"hi",
		"thread_id":"t1",
		"workdir":"/work",
		"user_bearer":"user-jwt"
	}`)
	var p WorkPayload
	if err := json.Unmarshal(raw, &p); err != nil {
		t.Fatal(err)
	}
	if p.UserBearer != "user-jwt" {
		t.Fatalf("UserBearer=%q", p.UserBearer)
	}
	if p.Workdir != "/work" {
		t.Fatalf("Workdir=%q", p.Workdir)
	}
	if p.ThreadID != "t1" {
		t.Fatalf("ThreadID=%q", p.ThreadID)
	}
}
