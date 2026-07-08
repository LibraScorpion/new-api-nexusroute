/*
agent-api Apps 页：应用消耗排行（对标 openrouter.ai/apps）
归因：客户端调用网关时自报 X-Title 请求头
*/
import { useQuery } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'

import { PublicLayout } from '@/components/layout'
import { Card, CardContent } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { api } from '@/lib/api'

type AppStat = {
  app: string
  tokens: number
  requests: number
}

type AppTrendingStat = AppStat & { growth_percent: number }

type AppRankings = {
  most_popular: AppStat[]
  trending: AppTrendingStat[]
}

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

export function Apps() {
  const { t } = useTranslation()
  const { data, isLoading } = useQuery({
    queryKey: ['app-rankings'],
    queryFn: getAppRankings,
  })

  const popular = data?.most_popular ?? []
  const trending = data?.trending ?? []

  return (
    <PublicLayout>
      <div className='mx-auto max-w-6xl space-y-10 px-4 py-10'>
        <div className='space-y-2'>
          <h1 className='text-3xl font-bold'>{t('App & Agent Rankings')}</h1>
          <p className='text-muted-foreground text-sm'>
            {t(
              'Largest apps and agents by token usage on this gateway. Send the X-Title header to appear here.'
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
                'No app usage recorded yet. Apps appear automatically once they call the API with an X-Title header.'
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
                      <div className='font-semibold'>{app.app}</div>
                      <AppAvatar name={app.app} size='lg' />
                    </div>
                    <div className='text-muted-foreground text-xs'>
                      {formatTokens(app.requests)} {t('requests')}
                    </div>
                    <div className='text-muted-foreground text-xs'>
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
                    <AppAvatar name={app.app} />
                    <div className='truncate text-sm font-medium'>
                      {app.app}
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
                    <AppAvatar name={app.app} />
                    <div className='min-w-0 flex-1'>
                      <div className='truncate text-sm font-medium'>
                        {app.app}
                      </div>
                      <div className='text-muted-foreground text-xs'>
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
