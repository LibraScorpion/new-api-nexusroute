package model

import (
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func attributionCtx(t *testing.T, headers map[string]string) *gin.Context {
	t.Helper()
	c, _ := gin.CreateTestContext(httptest.NewRecorder())
	c.Request = httptest.NewRequest("POST", "/v1/chat/completions", nil)
	for k, v := range headers {
		c.Request.Header.Set(k, v)
	}
	return c
}

func TestParseAppAttribution(t *testing.T) {
	cases := []struct {
		name       string
		headers    map[string]string
		app, title string
		categories []string
	}{
		{
			name: "referer domain is the identity",
			headers: map[string]string{
				"HTTP-Referer": "https://cline.bot/some/path",
				"X-Title":      "Cline",
			},
			app: "cline.bot", title: "Cline",
		},
		{
			name:    "no referer means no attribution",
			headers: map[string]string{"X-Title": "Orphan"},
			app:     "", title: "Orphan",
		},
		{
			name:    "localhost without title is not tracked",
			headers: map[string]string{"HTTP-Referer": "http://localhost:5173"},
			app:     "",
		},
		{
			name: "localhost with title keys by title",
			headers: map[string]string{
				"HTTP-Referer":       "http://localhost:5173",
				"X-OpenRouter-Title": "Local Dev App",
			},
			app: "Local Dev App", title: "Local Dev App",
		},
		{
			name: "X-OpenRouter-Title wins over X-Title",
			headers: map[string]string{
				"HTTP-Referer":       "https://myapp.com",
				"X-OpenRouter-Title": "New Name",
				"X-Title":            "Old Name",
			},
			app: "myapp.com", title: "New Name",
		},
		{
			name: "categories filtered to taxonomy, max 2, invalid ignored",
			headers: map[string]string{
				"HTTP-Referer":            "https://myapp.com",
				"X-OpenRouter-Categories": "bogus, cli-agent , IDE-EXTENSION, cloud-agent",
			},
			app: "myapp.com", categories: []string{"cli-agent", "ide-extension"},
		},
		{
			name: "control chars stripped and title capped at 64 runes",
			headers: map[string]string{
				"HTTP-Referer": "https://myapp.com",
				"X-Title":      "bad\x00name" + strings.Repeat("长", 100),
			},
			app: "myapp.com", title: "badname" + strings.Repeat("长", 57),
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			app, title, _, cats := parseAppAttribution(attributionCtx(t, tc.headers))
			assert.Equal(t, tc.app, app)
			if tc.title != "" {
				assert.Equal(t, tc.title, title)
			}
			assert.Equal(t, tc.categories, cats)
		})
	}
}

func TestMergeCategories(t *testing.T) {
	require.Equal(t, "cli-agent,game", mergeCategories("cli-agent", []string{"game", "cli-agent"}))
	require.Equal(t, "a,b", mergeCategories("a,b", nil))
	// 累计上限 10
	ten := make([]string, 12)
	for i := range ten {
		ten[i] = strings.Repeat("c", i+1)
	}
	require.Len(t, strings.Split(mergeCategories("", ten), ","), 10)
}
