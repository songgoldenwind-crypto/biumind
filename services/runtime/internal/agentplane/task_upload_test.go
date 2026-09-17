package agentplane

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/biumind/biumind/apps/cli/biu/pkg/biumindkit"
	"github.com/google/uuid"
)

func skipBuild(_ context.Context, _ WorkPayload) (*biumindkit.Agent, error) {
	return nil, nil
}

func testRegistrar(t *testing.T, h http.Handler) *Registrar {
	t.Helper()
	ts := httptest.NewServer(h)
	t.Cleanup(ts.Close)
	return &Registrar{
		cfg: Config{
			BrainURL:   ts.URL,
			Token:      "admin-jwt",
			HTTPClient: ts.Client(),
		},
		envID:  uuid.New(),
		logger: slog.New(slog.NewTextHandler(io.Discard, nil)),
	}
}

func TestRegistrar_UploadLocalFileAndPostArtifacts(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "week.md")
	if err := os.WriteFile(path, []byte("# week\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	var gotSource, gotAuth string
	var posted any
	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/files/upload", func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		if err := r.ParseMultipartForm(1 << 20); err != nil {
			t.Errorf("multipart: %v", err)
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		gotSource = r.FormValue("source")
		if _, _, err := r.FormFile("file"); err != nil {
			t.Errorf("file: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"id":"file-1"}`))
	})
	mux.HandleFunc("POST /v1/threads/{id}/task-artifacts", func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(body, &posted)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"id":"t1"}`))
	})
	reg := testRegistrar(t, mux)
	id, err := reg.UploadLocalFile(context.Background(), "user-jwt", path, "week.md",
		"text/markdown", map[string]string{"thread_id": "t1", "path": path})
	if err != nil {
		t.Fatal(err)
	}
	if id != "file-1" {
		t.Fatalf("id=%q", id)
	}
	if gotAuth != "Bearer user-jwt" {
		t.Fatalf("auth=%q (must be user JWT, not admin)", gotAuth)
	}
	if gotSource != "task-artifact" {
		t.Fatalf("source=%q", gotSource)
	}
	if err := reg.PostTaskArtifacts(context.Background(), "user-jwt", "t1", []map[string]string{{
		"file_id": id, "path": path, "kind": "markdown", "title": "week.md",
	}}); err != nil {
		t.Fatal(err)
	}
	m, _ := posted.(map[string]any)
	arts, _ := m["artifacts"].([]any)
	if len(arts) != 1 {
		t.Fatalf("posted=%v", posted)
	}
}

func TestRegistrar_UploadLocalFileRejectsEmptyBearer(t *testing.T) {
	reg := testRegistrar(t, http.NewServeMux())
	_, err := reg.UploadLocalFile(context.Background(), "", "/nope", "x", "text/plain", nil)
	if err == nil {
		t.Fatal("expected empty bearer error")
	}
}

func TestWorker_syncTaskArtifactsUploadFailureDoesNotPanic(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "week.md")
	if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/files/upload", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
		_, _ = w.Write([]byte(`{"error":"minio"}`))
	})
	reg := testRegistrar(t, mux)
	w := NewWorker(reg, skipBuild, WorkerConfig{}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	w.syncTaskArtifacts(context.Background(), WorkPayload{
		UserBearer: "user-jwt",
		ThreadID:   "t1",
	}, []string{path})
}

func TestWorker_syncTaskArtifactsSkipsWithoutBearer(t *testing.T) {
	called := false
	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/files/upload", func(w http.ResponseWriter, _ *http.Request) {
		called = true
		w.WriteHeader(http.StatusInternalServerError)
	})
	reg := testRegistrar(t, mux)
	w := NewWorker(reg, skipBuild, WorkerConfig{}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	dir := t.TempDir()
	path := filepath.Join(dir, "week.md")
	if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	w.syncTaskArtifacts(context.Background(), WorkPayload{ThreadID: "t1"}, []string{path})
	if called {
		t.Fatal("must not upload with admin token when user bearer is empty")
	}
}
