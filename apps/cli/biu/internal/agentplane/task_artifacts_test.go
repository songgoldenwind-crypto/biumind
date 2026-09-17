package agentplane

import (
	"path/filepath"
	"runtime"
	"testing"
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
	if !isTempArtifactPath("/Users/me/week.tmp") {
		t.Fatal(".tmp should be temp")
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

func TestNoteWriteCandidate(t *testing.T) {
	root := t.TempDir()
	week := filepath.Join(root, "week.md")
	tmp := filepath.Join(root, ".draft.md")
	var cands []string
	cands = noteWriteCandidate(cands, "Write", map[string]any{"file_path": week}, root, false)
	cands = noteWriteCandidate(cands, "Write", map[string]any{"file_path": tmp}, root, false)
	cands = noteWriteCandidate(cands, "Read", map[string]any{"file_path": week}, root, false)
	cands = noteWriteCandidate(cands, "Write", map[string]any{"file_path": week}, root, true)
	if len(cands) != 1 || cands[0] != week {
		t.Fatalf("cands=%v", cands)
	}
}

func TestPickPrimaryArtifactPath(t *testing.T) {
	root := t.TempDir()
	a := filepath.Join(root, "a.md")
	b := filepath.Join(root, "b.csv")
	got := pickPrimaryArtifactPath([]string{a, b})
	if got != b {
		t.Fatalf("got %q want last %q", got, b)
	}
	if pickPrimaryArtifactPath(nil) != "" {
		t.Fatal("empty should be empty")
	}
}

func TestMimeFromPath(t *testing.T) {
	if mimeFromPath("week.md") != "text/markdown" {
		t.Fatal("md")
	}
	if mimeFromPath("t.pptx") != "application/vnd.openxmlformats-officedocument.presentationml.presentation" {
		t.Fatal("pptx")
	}
}

func TestKindFromPath(t *testing.T) {
	if kindFromPath("week.md") != "markdown" {
		t.Fatal("md kind")
	}
	if kindFromPath("t.xlsx") != "sheet" {
		t.Fatal("xlsx kind")
	}
	if kindFromPath("x.bin") != "file" {
		t.Fatal("other kind")
	}
}

func TestTrackWriteStartAndResult(t *testing.T) {
	root := t.TempDir()
	week := filepath.Join(root, "week.md")
	pending := map[string]string{}
	trackWriteStart(pending, "Write", "tu1", map[string]any{"file_path": week}, root)
	if pending["tu1"] != week {
		t.Fatalf("pending=%v", pending)
	}
	cands := trackWriteResult(pending, nil, "tu1", false, root)
	if len(cands) != 1 || cands[0] != week {
		t.Fatalf("cands=%v", cands)
	}
	if len(pending) != 0 {
		t.Fatalf("pending should clear: %v", pending)
	}
	trackWriteStart(pending, "Write", "tu2", map[string]any{"file_path": week}, root)
	cands = trackWriteResult(pending, nil, "tu2", true, root)
	if len(cands) != 0 {
		t.Fatalf("error write should skip: %v", cands)
	}
}
