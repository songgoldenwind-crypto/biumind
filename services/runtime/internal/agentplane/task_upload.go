package agentplane

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"strings"
)

// UploadLocalFile POSTs multipart /v1/files/upload with the user's JWT.
// Admin runtime token must not own the file — empty bearer is an error.
func (r *Registrar) UploadLocalFile(ctx context.Context, bearer, path, filename, mime string, meta map[string]string) (string, error) {
	if r == nil {
		return "", fmt.Errorf("upload: nil registrar")
	}
	if strings.TrimSpace(bearer) == "" {
		return "", fmt.Errorf("upload: empty user bearer")
	}
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	part, err := mw.CreateFormFile("file", filename)
	if err != nil {
		return "", err
	}
	if _, err := io.Copy(part, f); err != nil {
		return "", err
	}
	if err := mw.WriteField("source", "task-artifact"); err != nil {
		return "", err
	}
	if len(meta) > 0 {
		raw, err := json.Marshal(meta)
		if err != nil {
			return "", err
		}
		if err := mw.WriteField("metadata", string(raw)); err != nil {
			return "", err
		}
	}
	if err := mw.Close(); err != nil {
		return "", err
	}
	req, err := r.newUserReq(ctx, http.MethodPost, "/v1/files/upload", bearer, &buf)
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", mw.FormDataContentType())
	resp, err := r.httpClient().Do(req)
	if err != nil {
		return "", fmt.Errorf("upload file: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return "", parseAPIError(resp)
	}
	var out struct {
		ID string `json:"id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", fmt.Errorf("decode upload: %w", err)
	}
	if out.ID == "" {
		return "", fmt.Errorf("upload: empty file id")
	}
	return out.ID, nil
}

// PostTaskArtifacts merges metadata.task.artifacts on the thread.
func (r *Registrar) PostTaskArtifacts(ctx context.Context, bearer, threadID string, artifacts []map[string]string) error {
	if r == nil || threadID == "" || len(artifacts) == 0 {
		return nil
	}
	if strings.TrimSpace(bearer) == "" {
		return fmt.Errorf("post task artifacts: empty user bearer")
	}
	items := make([]map[string]any, 0, len(artifacts))
	for _, a := range artifacts {
		item := map[string]any{}
		for k, v := range a {
			if v != "" {
				item[k] = v
			}
		}
		items = append(items, item)
	}
	body := map[string]any{"artifacts": items}
	raw, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := r.newUserReq(ctx, http.MethodPost,
		"/v1/threads/"+threadID+"/task-artifacts", bearer, bytes.NewReader(raw))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := r.httpClient().Do(req)
	if err != nil {
		return fmt.Errorf("post task artifacts: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return parseAPIError(resp)
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	return nil
}

func (r *Registrar) newUserReq(ctx context.Context, method, path, bearer string, body io.Reader) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, method, r.cfg.BrainURL+path, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(bearer))
	return req, nil
}

func (r *Registrar) httpClient() *http.Client {
	if r.cfg.HTTPClient != nil {
		return r.cfg.HTTPClient
	}
	return http.DefaultClient
}

func (w *Worker) syncTaskArtifacts(ctx context.Context, payload WorkPayload, cands []string) {
	if w == nil || w.reg == nil {
		return
	}
	if strings.TrimSpace(payload.UserBearer) == "" || payload.ThreadID == "" {
		return
	}
	primary := pickPrimaryArtifactPath(cands)
	if primary == "" {
		return
	}
	st, err := os.Stat(primary)
	if err != nil || st.IsDir() {
		return
	}
	fileID, err := w.reg.UploadLocalFile(ctx, payload.UserBearer, primary,
		artifactTitle(primary), mimeFromPath(primary), map[string]string{
			"thread_id": payload.ThreadID,
			"path":      primary,
			"kind":      kindFromPath(primary),
		})
	if err != nil {
		w.logger.Warn("task artifact upload failed",
			"thread_id", payload.ThreadID, "path", primary, "err", err)
		return
	}
	if err := w.reg.PostTaskArtifacts(ctx, payload.UserBearer, payload.ThreadID, []map[string]string{{
		"file_id": fileID,
		"path":    primary,
		"kind":    kindFromPath(primary),
		"title":   artifactTitle(primary),
	}}); err != nil {
		w.logger.Warn("task artifact metadata failed",
			"thread_id", payload.ThreadID, "file_id", fileID, "err", err)
	}
}
