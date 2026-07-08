/*
agent-api Apps 页：应用消耗排行（对标 openrouter.ai/apps）
归因遵循 OpenRouter 规范：HTTP-Referer 必填（域名=标识），
X-OpenRouter-Title/X-Title 显示名，X-OpenRouter-Categories 分类
*/
import { useQuery } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'

import { PublicLayout } from '@/components/layout'
import { Card, CardContent } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { api } from '@/lib/api'

type AppStat = {
  app: string
  title: string
  url: string
  categories: string[]
  tokens: number
  requests: number
}

type AppTrendingStat = AppStat & { growth_percent: number }

type AppRankings = {
  most_popular: AppStat[] | null
  trending: AppTrendingStat[] | null
  top_categories: Record<string, AppStat[]> | null
}

const CATEGORY_GROUPS: { key: string; label: string }[] = [
  { key: 'coding', label: 'Top Coding Agents' },
  { key: 'productivity', label: 'Top Productivity' },
  { key: 'creative', label: 'Top Creative' },
  { key: 'entertainment', label: 'Top Entertainment' },
]

async function getAppRankings(): Promise<AppRankings> {
  const res = await api.get('/api/apps/rankings')
  return res.data.data
}

function formatTokens(n: number): string {
  if (n >= 1e12) return (n / 1e12).toFixed(2) + 'T'
  if (n >= 1e9) return (n / 1e9).toFixed(1) + 'B'
  if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M'
  if (n >= 1e3) return (n / 1e3).toFixed(1) + 'K'
  return String(n)
}

const AVATAR_COLORS = [
  'bg-blue-600',
  'bg-emerald-600',
  'bg-violet-600',
  'bg-amber-600',
  'bg-rose-600',
  'bg-cyan-600',
]

function AppAvatar({ name, size = 'md' }: { name: string; size?: 'md' | 'lg' }) {
  const color = AVATAR_COLORS[(name.codePointAt(0) ?? 0) % AVATAR_COLORS.length]
  return (
    <div
      className={`${color} flex shrink-0 items-center justify-center rounded-lg font-semibold text-white ${
        size === 'lg' ? 'h-10 w-10 text-lg' : 'h-8 w-8 text-sm'
      }`}
    >
      {[...name][0]?.toUpperCase()}
    </div>
  )
}

function AppDomain({ app }: { app: AppStat }) {
  if (!app.url) return null
  return (
    <a
      href={app.url}
      target='_blank'
      rel='noopener noreferrer'
      className='text-muted-foreground block truncate text-xs hover:underline'
    >
      {app.url.replace(/^https?:\/\//, '')}
    </a>
  )
}

export function Apps() {
  const { t } = useTranslation()
  const { data, isLoading } = useQuery({
    queryKey: ['app-rankings'],
    queryFn: getAppRankings,
  })

  const popular = data?.most_popular ?? []
  const trending = data?.trending ?? []
  const topCategories = data?.top_categories ?? {}

  return (
    <PublicLayout>
      <div className='mx-auto max-w-6xl space-y-10 px-4 py-10'>
        <div className='space-y-2'>
          <h1 className='text-3xl font-bold'>{t('App & Agent Rankings')}</h1>
          <p className='text-muted-foreground text-sm'>
            {t(
              'Largest apps and agents by token usage on this gateway. Send the HTTP-Referer and X-Title headers to appear here.'
            )}
          </p>
        </div>

        {isLoading && (
          <div className='grid gap-4 sm:grid-cols-2 lg:grid-cols-4'>
            {Array.from({ length: 4 }).map((_, i) => (
              <Skeleton key={i} className='h-32' />
            ))}
          </div>
        )}

        {!isLoading && popular.length === 0 && (
          <Card>
            <CardContent className='text-muted-foreground py-16 text-center text-sm'>
              {t(
                'No app usage recorded yet. Apps appear automatically once they call the API with attribution headers.'
              )}
            </CardContent>
          </Card>
        )}

        {popular.length > 0 && (
          <section className='space-y-4'>
            <h2 className='text-xl font-semibold'>{t('Most Popular')}</h2>
            <div className='grid gap-4 sm:grid-cols-2 lg:grid-cols-4'>
              {popular.slice(0, 4).map((app) => (
                <Card key={app.app}>
                  <CardContent className='space-y-3 p-5'>
                    <div className='flex items-start justify-between gap-2'>
                      <div className='min-w-0'>
                        <div className='truncate font-semibold'>
                          {app.title}
                        </div>
                        <AppDomain app={app} />
                      </div>
                      <AppAvatar name={app.title} size='lg' />
                    </div>
                    <div className='text-muted-foreground text-xs'>
                      {formatTokens(app.requests)} {t('requests')} ·{' '}
                      {formatTokens(app.tokens)} tokens
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          </section>
        )}

        {trending.length > 0 && (
          <section className='space-y-4'>
            <div className='flex items-baseline justify-between'>
              <h2 className='text-xl font-semibold'>{t('Trending')}</h2>
              <span className='text-muted-foreground text-xs'>
                {t('Fastest growing this week')}
              </span>
            </div>
            <div className='grid gap-3 sm:grid-cols-3 lg:grid-cols-6'>
              {trending.slice(0, 6).map((app) => (
                <Card key={app.app}>
                  <CardContent className='space-y-2 p-4'>
                    <AppAvatar name={app.title} />
                    <div className='truncate text-sm font-medium'>
                      {app.title}
                    </div>
                    <div className='flex items-center justify-between text-xs'>
                      <span className='text-muted-foreground'>
                        {formatTokens(app.tokens)}
                      </span>
                      <span className='font-medium text-emerald-600'>
                        {app.growth_percent >= 999
                          ? '>999%'
                          : `+${app.growth_percent}%`}
                      </span>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          </section>
        )}

        {CATEGORY_GROUPS.some((g) => (topCategories[g.key] ?? []).length > 0) && (
          <div className='grid gap-6 lg:grid-cols-2'>
            {CATEGORY_GROUPS.filter(
              (g) => (topCategories[g.key] ?? []).length > 0
            ).map((group) => (
              <section key={group.key} className='space-y-3'>
                <h2 className='text-lg font-semibold'>{t(group.label)}</h2>
                <Card>
                  <CardContent className='divide-y p-0'>
                    {(topCategories[group.key] ?? []).map((app, i) => (
                      <div
                        key={app.app}
                        className='flex items-center gap-3 px-4 py-2.5'
                      >
                        <span className='text-muted-foreground w-5 text-right text-sm'>
                          {i + 1}.
                        </span>
                        <AppAvatar name={app.title} />
                        <div className='min-w-0 flex-1'>
                          <div className='truncate text-sm font-medium'>
                            {app.title}
                          </div>
                          <AppDomain app={app} />
                        </div>
                        <div className='text-sm'>
                          {formatTokens(app.tokens)}{' '}
                          <span className='text-muted-foreground'>tokens</span>
                        </div>
                      </div>
                    ))}
                  </CardContent>
                </Card>
              </section>
            ))}
          </div>
        )}

        {popular.length > 0 && (
          <section className='space-y-4'>
            <h2 className='text-xl font-semibold'>{t('All Apps')}</h2>
            <Card>
              <CardContent className='divide-y p-0'>
                {popular.map((app, i) => (
                  <div
                    key={app.app}
                    className='flex items-center gap-4 px-5 py-3'
                  >
                    <span className='text-muted-foreground w-6 text-right text-sm'>
                      {i + 1}.
                    </span>
                    <AppAvatar name={app.title} />
                    <div className='min-w-0 flex-1'>
                      <div className='truncate text-sm font-medium'>
                        {app.title}
                      </div>
                      <div className='text-muted-foreground truncate text-xs'>
                        {app.url
                          ? app.url.replace(/^https?:\/\//, '') + ' · '
                          : ''}
                        {formatTokens(app.requests)} {t('requests')}
                      </div>
                    </div>
                    <div className='text-sm font-medium'>
                      {formatTokens(app.tokens)}{' '}
                      <span className='text-muted-foreground font-normal'>
                        tokens
                      </span>
                    </div>
                  </div>
                ))}
              </CardContent>
            </Card>
          </section>
        )}
      </div>
    </PublicLayout>
  )
}
