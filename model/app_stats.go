package model

import (
	"strings"
	"unicode"

	"github.com/QuantumNous/new-api/common"
)

// sanitizeAppTitle 归一化客户端自报的 X-Title：去首尾空白、剔除控制字符、限长 64 字符
func sanitizeAppTitle(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return ""
	}
	s = strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return -1
		}
		return r
	}, s)
	runes := []rune(s)
	if len(runes) > 64 {
		runes = runes[:64]
	}
	return string(runes)
}

type AppStat struct {
	App      string `json:"app"`
	Tokens   int64  `json:"tokens"`
	Requests int64  `json:"requests"`
}

type AppTrendingStat struct {
	AppStat
	GrowthPercent int64 `json:"growth_percent"` // 本周 vs 上周 token 增速，封顶 999；上周为 0 记 999（新上榜）
}

type AppRankings struct {
	MostPopular []AppStat         `json:"most_popular"` // 累计 token 消耗 Top N
	Trending    []AppTrendingStat `json:"trending"`     // 近 7 天消耗 Top N + 周环比增速
}

func appStatsSince(since int64, limit int) ([]AppStat, error) {
	var stats []AppStat
	tx := LOG_DB.Table("logs").
		Select("app, COALESCE(SUM(prompt_tokens),0)+COALESCE(SUM(completion_tokens),0) AS tokens, COUNT(*) AS requests").
		Where("type = ? AND app <> ''", LogTypeConsume)
	if since > 0 {
		tx = tx.Where("created_at >= ?", since)
	}
	err := tx.Group("app").Order("tokens DESC").Limit(limit).Scan(&stats).Error
	return stats, err
}

func GetAppRankings() (*AppRankings, error) {
	popular, err := appStatsSince(0, 20)
	if err != nil {
		return nil, err
	}
	now := common.GetTimestamp()
	week := int64(7 * 24 * 3600)
	current, err := appStatsSince(now-week, 12)
	if err != nil {
		return nil, err
	}
	prev, err := appStatsSince(now-2*week, 1000)
	if err != nil {
		return nil, err
	}
	// prev 含最近两周，减去本周得上一周
	curMap := map[string]int64{}
	for _, s := range current {
		curMap[s.App] = s.Tokens
	}
	prevMap := map[string]int64{}
	for _, s := range prev {
		prevMap[s.App] = s.Tokens - curMap[s.App]
	}
	trending := make([]AppTrendingStat, 0, len(current))
	for _, s := range current {
		g := int64(999)
		if p := prevMap[s.App]; p > 0 {
			g = (s.Tokens - p) * 100 / p
			if g > 999 {
				g = 999
			}
		}
		trending = append(trending, AppTrendingStat{AppStat: s, GrowthPercent: g})
	}
	return &AppRankings{MostPopular: popular, Trending: trending}, nil
}
