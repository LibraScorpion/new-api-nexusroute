package model

import (
	"net/url"
	"strings"
	"sync"
	"unicode"

	"github.com/QuantumNous/new-api/common"
	"github.com/gin-gonic/gin"
)

// 应用归因，兼容 OpenRouter 规范（openrouter.ai/docs/app-attribution）：
//   HTTP-Referer            必填，域名 = 应用唯一标识
//   X-OpenRouter-Title      显示名（兼容旧 X-Title）；localhost 应用必须带 title 才入榜（此时以 title 为标识）
//   X-OpenRouter-Categories 分类，每请求最多 2 个，非法值静默忽略

var appCategoryGroup = map[string]string{
	"cli-agent": "coding", "ide-extension": "coding", "cloud-agent": "coding",
	"programming-app": "coding", "native-app-builder": "coding",
	"creative-writing": "creative", "video-gen": "creative", "image-gen": "creative",
	"writing-assistant": "productivity", "general-chat": "productivity", "personal-agent": "productivity",
	"roleplay": "entertainment", "game": "entertainment",
}

// AppInfo 应用元数据（主库），logs.app 为其外键（App 字段）
type AppInfo struct {
	Id         int    `json:"id"`
	App        string `json:"app" gorm:"type:varchar(64);uniqueIndex"`
	Title      string `json:"title" gorm:"type:varchar(64);default:''"`
	Url        string `json:"url" gorm:"type:varchar(128);default:''"`
	Categories string `json:"categories" gorm:"type:varchar(256);default:''"` // 逗号分隔，累计上限 10
	CreatedAt  int64  `json:"created_at" gorm:"bigint"`
	UpdatedAt  int64  `json:"updated_at" gorm:"bigint"`
}

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

func isLocalHost(host string) bool {
	return host == "localhost" || host == "127.0.0.1" || host == "::1"
}

// parseAppAttribution 从请求头解析 (app 标识, 显示名, 来源 origin, 合法分类)
// 返回 app == "" 表示本次请求不归因
func parseAppAttribution(c *gin.Context) (app, title, origin string, categories []string) {
	title = sanitizeAppTitle(c.GetHeader("X-OpenRouter-Title"))
	if title == "" {
		title = sanitizeAppTitle(c.GetHeader("X-Title"))
	}
	referer := strings.TrimSpace(c.GetHeader("HTTP-Referer"))
	if referer == "" {
		referer = strings.TrimSpace(c.Request.Referer())
	}
	if referer == "" {
		return "", title, "", nil
	}
	u, err := url.Parse(referer)
	if err != nil || u.Hostname() == "" {
		return "", title, "", nil
	}
	host := strings.ToLower(u.Hostname())
	if isLocalHost(host) {
		if title == "" {
			return "", "", "", nil // 规范：localhost 无 title 不入榜
		}
		app = title
	} else {
		app = host
	}
	app = sanitizeAppTitle(app)
	origin = u.Scheme + "://" + u.Host
	for _, raw := range strings.Split(c.GetHeader("X-OpenRouter-Categories"), ",") {
		cat := strings.ToLower(strings.TrimSpace(raw))
		if _, ok := appCategoryGroup[cat]; ok {
			categories = append(categories, cat)
			if len(categories) == 2 { // 规范：每请求最多 2 个
				break
			}
		}
	}
	return app, title, origin, categories
}

// appInfoCache 挡掉每请求一次的 upsert；value = title|url|categories 摘要
var appInfoCache sync.Map

func upsertAppInfo(app, title, origin string, categories []string) {
	if app == "" {
		return
	}
	digest := title + "|" + origin + "|" + strings.Join(categories, ",")
	if v, ok := appInfoCache.Load(app); ok && v.(string) == digest {
		return
	}
	var info AppInfo
	now := common.GetTimestamp()
	if err := DB.Where("app = ?", app).First(&info).Error; err != nil {
		info = AppInfo{App: app, Title: title, Url: origin,
			Categories: strings.Join(categories, ","), CreatedAt: now, UpdatedAt: now}
		if err := DB.Create(&info).Error; err != nil {
			common.SysError("failed to create app info: " + err.Error())
			return
		}
	} else {
		merged := mergeCategories(info.Categories, categories)
		if info.Title != title || info.Url != origin || info.Categories != merged {
			info.Title, info.Url, info.Categories, info.UpdatedAt = title, origin, merged, now
			if err := DB.Save(&info).Error; err != nil {
				common.SysError("failed to update app info: " + err.Error())
				return
			}
		}
	}
	appInfoCache.Store(app, digest)
}

// mergeCategories 已知分类 ∪ 新分类，保序去重，累计上限 10（规范）
func mergeCategories(existing string, incoming []string) string {
	seen := map[string]bool{}
	var out []string
	for _, c := range append(strings.Split(existing, ","), incoming...) {
		c = strings.TrimSpace(c)
		if c == "" || seen[c] {
			continue
		}
		seen[c] = true
		out = append(out, c)
		if len(out) == 10 {
			break
		}
	}
	return strings.Join(out, ",")
}

// recordAppAttribution 供 RecordConsumeLog 调用：返回 app 标识并维护元数据
func recordAppAttribution(c *gin.Context) string {
	app, title, origin, categories := parseAppAttribution(c)
	upsertAppInfo(app, title, origin, categories)
	return app
}

type AppStat struct {
	App        string   `json:"app"`
	Title      string   `json:"title"`
	Url        string   `json:"url"`
	Categories []string `json:"categories"`
	Tokens     int64    `json:"tokens"`
	Requests   int64    `json:"requests"`
}

type AppTrendingStat struct {
	AppStat
	GrowthPercent int64 `json:"growth_percent"` // 本周 vs 上周增速，封顶 999；上周为 0 记 999（新上榜）
}

type AppRankings struct {
	MostPopular   []AppStat                    `json:"most_popular"`
	Trending      []AppTrendingStat            `json:"trending"`
	TopCategories map[string][]AppStat         `json:"top_categories"` // coding/creative/productivity/entertainment → Top5
}

type appAgg struct {
	App      string
	Tokens   int64
	Requests int64
}

func appStatsSince(since int64, limit int) ([]appAgg, error) {
	var stats []appAgg
	tx := LOG_DB.Table("logs").
		Select("app, COALESCE(SUM(prompt_tokens),0)+COALESCE(SUM(completion_tokens),0) AS tokens, COUNT(*) AS requests").
		Where("type = ? AND app <> ''", LogTypeConsume)
	if since > 0 {
		tx = tx.Where("created_at >= ?", since)
	}
	err := tx.Group("app").Order("tokens DESC").Limit(limit).Scan(&stats).Error
	return stats, err
}

func decorate(aggs []appAgg, infos map[string]AppInfo) []AppStat {
	out := make([]AppStat, 0, len(aggs))
	for _, a := range aggs {
		s := AppStat{App: a.App, Title: a.App, Tokens: a.Tokens, Requests: a.Requests, Categories: []string{}}
		if info, ok := infos[a.App]; ok {
			if info.Title != "" {
				s.Title = info.Title
			}
			s.Url = info.Url
			if info.Categories != "" {
				s.Categories = strings.Split(info.Categories, ",")
			}
		}
		out = append(out, s)
	}
	return out
}

func GetAppRankings() (*AppRankings, error) {
	popularAgg, err := appStatsSince(0, 50)
	if err != nil {
		return nil, err
	}
	now := common.GetTimestamp()
	week := int64(7 * 24 * 3600)
	currentAgg, err := appStatsSince(now-week, 12)
	if err != nil {
		return nil, err
	}
	prevAgg, err := appStatsSince(now-2*week, 1000)
	if err != nil {
		return nil, err
	}

	keys := map[string]bool{}
	for _, a := range popularAgg {
		keys[a.App] = true
	}
	for _, a := range currentAgg {
		keys[a.App] = true
	}
	var names []string
	for k := range keys {
		names = append(names, k)
	}
	infos := map[string]AppInfo{}
	if len(names) > 0 {
		var rows []AppInfo
		if err := DB.Where("app IN ?", names).Find(&rows).Error; err == nil {
			for _, r := range rows {
				infos[r.App] = r
			}
		}
	}

	popular := decorate(popularAgg, infos)
	current := decorate(currentAgg, infos)

	curMap := map[string]int64{}
	for _, s := range currentAgg {
		curMap[s.App] = s.Tokens
	}
	prevMap := map[string]int64{}
	for _, s := range prevAgg {
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

	topCategories := map[string][]AppStat{}
	for _, s := range popular {
		grouped := map[string]bool{}
		for _, cat := range s.Categories {
			group := appCategoryGroup[cat]
			if group == "" || grouped[group] || len(topCategories[group]) >= 5 {
				continue
			}
			grouped[group] = true
			topCategories[group] = append(topCategories[group], s)
		}
	}

	return &AppRankings{MostPopular: popular, Trending: trending, TopCategories: topCategories}, nil
}
