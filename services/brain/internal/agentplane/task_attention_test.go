package agentplane

import (
	"testing"

	chatpkg "github.com/biumind/biumind/services/brain/internal/chat"
)

func TestClassifyTaskFrame(t *testing.T) {
	cases := []struct {
		name    string
		payload string
		want    string
		reason  string
		ok      bool
	}{
		{
			name:    "permission",
			payload: `{"type":"control_request","request":{"subtype":"can_use_tool"}}`,
			want:    chatpkg.EventTaskAttention,
			reason:  "approval",
			ok:      true,
		},
		{
			name:    "elicitation",
			payload: `{"type":"control_request","request":{"subtype":"elicitation"}}`,
			want:    chatpkg.EventTaskAttention,
			reason:  "elicitation",
			ok:      true,
		},
		{
			name:    "other control",
			payload: `{"type":"control_request","request":{"subtype":"interrupt"}}`,
			ok:      false,
		},
		{
			name:    "result success",
			payload: `{"type":"result","subtype":"success","is_error":false}`,
			want:    chatpkg.EventTaskCompleted,
			reason:  "success",
			ok:      true,
		},
		{
			name:    "result error",
			payload: `{"type":"result","subtype":"error","is_error":true}`,
			want:    chatpkg.EventTaskFailed,
			reason:  "error",
			ok:      true,
		},
		{
			name:    "text ignored",
			payload: `{"type":"assistant","text":"hi"}`,
			ok:      false,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, reason, ok := ClassifyTaskFrame([]byte(tc.payload))
			if ok != tc.ok || got != tc.want || reason != tc.reason {
				t.Fatalf("got (%q,%q,%v) want (%q,%q,%v)", got, reason, ok, tc.want, tc.reason, tc.ok)
			}
		})
	}
}

func TestTaskFrameToolName(t *testing.T) {
	got := taskFrameToolName([]byte(`{"type":"control_request","request":{"subtype":"can_use_tool","tool_name":"Write"}}`))
	if got != "Write" {
		t.Fatalf("got %q", got)
	}
	if taskFrameToolName([]byte(`{"type":"result"}`)) != "" {
		t.Fatal("result should have no tool")
	}
}
