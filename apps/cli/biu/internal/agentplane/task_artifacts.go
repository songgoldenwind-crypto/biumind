package agentplane

import (
	"path"
	"path/filepath"
	"strings"
)

func isWriteLikeTool(name string) bool {
	switch strings.ToLower(strings.TrimSpace(name)) {
	case "write", "edit", "multiedit", "notebookedit":
		return true
	default:
		return false
	}
}

func isTempArtifactPath(p string) bool {
	n := strings.ToLower(strings.ReplaceAll(p, "\\", "/"))
	base := n
	if i := strings.LastIndex(n, "/"); i >= 0 {
		base = n[i+1:]
	}
	if strings.HasPrefix(base, ".") {
		return true
	}
	if strings.HasSuffix(base, ".tmp") || strings.HasSuffix(base, ".swp") {
		return true
	}
	if strings.Contains(n, "/tmp/") || strings.HasSuffix(n, "/tmp") {
		return true
	}
	return false
}

func resolveToolPath(p, workdir string) string {
	p = strings.TrimSpace(p)
	if p == "" {
		return ""
	}
	if filepath.IsAbs(p) {
		return filepath.Clean(p)
	}
	if strings.TrimSpace(workdir) == "" {
		return filepath.Clean(p)
	}
	return filepath.Clean(filepath.Join(workdir, p))
}

func pathInWorkdir(p, workdir string) bool {
	if strings.TrimSpace(workdir) == "" {
		return true
	}
	absP, err := filepath.Abs(p)
	if err != nil {
		return false
	}
	absW, err := filepath.Abs(workdir)
	if err != nil {
		return false
	}
	rel, err := filepath.Rel(absW, absP)
	if err != nil {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

func toolPathFromInput(input map[string]any) string {
	if input == nil {
		return ""
	}
	for _, key := range []string{"file_path", "path"} {
		if s, ok := input[key].(string); ok && strings.TrimSpace(s) != "" {
			return strings.TrimSpace(s)
		}
	}
	return ""
}

// noteWriteCandidate appends an authorized write path. isError skips failed tools.
func noteWriteCandidate(cands []string, toolName string, input map[string]any, workdir string, isError bool) []string {
	if isError || !isWriteLikeTool(toolName) {
		return cands
	}
	raw := toolPathFromInput(input)
	full := resolveToolPath(raw, workdir)
	if full == "" || isTempArtifactPath(full) || !pathInWorkdir(full, workdir) {
		return cands
	}
	for _, existing := range cands {
		if existing == full {
			return cands
		}
	}
	return append(cands, full)
}

func pickPrimaryArtifactPath(paths []string) string {
	var last string
	for _, p := range paths {
		if p == "" || isTempArtifactPath(p) {
			continue
		}
		last = p
	}
	return last
}

func mimeFromPath(p string) string {
	switch strings.ToLower(filepath.Ext(p)) {
	case ".md", ".markdown":
		return "text/markdown"
	case ".csv":
		return "text/csv"
	case ".json":
		return "application/json"
	case ".pdf":
		return "application/pdf"
	case ".html", ".htm":
		return "text/html"
	case ".pptx":
		return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
	case ".xlsx":
		return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
	case ".png":
		return "image/png"
	case ".jpg", ".jpeg":
		return "image/jpeg"
	default:
		return "application/octet-stream"
	}
}

func kindFromPath(p string) string {
	switch strings.ToLower(filepath.Ext(p)) {
	case ".md", ".markdown":
		return "markdown"
	case ".pptx", ".ppt":
		return "ppt"
	case ".xlsx", ".xls", ".csv":
		return "sheet"
	case ".pdf":
		return "pdf"
	case ".html", ".htm":
		return "html"
	case ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg":
		return "image"
	default:
		return "file"
	}
}

func artifactTitle(p string) string {
	base := path.Base(strings.ReplaceAll(p, "\\", "/"))
	if base == "" || base == "." || base == "/" {
		return p
	}
	return base
}

func trackWriteStart(pending map[string]string, name, id string, input map[string]any, workdir string) {
	if pending == nil || id == "" || !isWriteLikeTool(name) {
		return
	}
	full := resolveToolPath(toolPathFromInput(input), workdir)
	if full != "" {
		pending[id] = full
	}
}

func trackWriteResult(pending map[string]string, cands []string, id string, isError bool, workdir string) []string {
	if pending == nil {
		return cands
	}
	full, ok := pending[id]
	if !ok {
		return cands
	}
	delete(pending, id)
	return noteWriteCandidate(cands, "Write", map[string]any{"file_path": full}, workdir, isError)
}
