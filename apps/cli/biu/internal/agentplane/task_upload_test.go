package agentplane

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

func TestClient_UploadLocalFileAndPostArtifacts(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "week.md")
	if err := os.WriteFile(path, []byte("# week\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	var gotSource, gotMeta, gotAuth string
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
		gotMeta = r.FormValue("metadata")
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
	_, c := stubServer(t, mux)
	id, err := c.UploadLocalFile(context.Background(), "user-jwt", path, "week.md",
		"text/markdown", map[string]string{"thread_id": "t1", "path": path})
	if err != nil {
		t.Fatal(err)
	}
	if id != "file-1" {
		t.Fatalf("id=%q", id)
	}
	if gotAuth != "Bearer user-jwt" {
		t.Fatalf("auth=%q", gotAuth)
	}
	if gotSource != "task-artifact" {
		t.Fatalf("source=%q", gotSource)
	}
	if gotMeta == "" {
		t.Fatal("metadata missing")
	}
	if err := c.PostTaskArtifacts(context.Background(), "user-jwt", "t1", []map[string]string{{
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

func TestClient_UploadLocalFileFailure(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/files/upload", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
		_, _ = w.Write([]byte(`{"error":{"code":"minio","message":"down"}}`))
	})
	_, c := stubServer(t, mux)
	dir := t.TempDir()
	path := filepath.Join(dir, "week.md")
	if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := c.UploadLocalFile(context.Background(), "", path, "week.md", "text/markdown", nil)
	if err == nil {
		t.Fatal("expected upload error")
	}
}
