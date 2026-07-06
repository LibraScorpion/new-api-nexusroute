// ponytail: 零依赖 mock 上游（OpenRouter 风格），验收用；有真实 Key 后直接换渠道 base_url 复验
// 用法: node server.mjs            → 正常上游 :8100
//       PORT=8101 FAIL=1 node …   → 永远 500 的坏上游（B1 fallback 验收）
//       TTFT_MS=800 node …        → 首字延迟注入（B3 验收）
import http from 'node:http';

const PORT = Number(process.env.PORT || 8100);
const FAIL = process.env.FAIL === '1';
const TTFT_MS = Number(process.env.TTFT_MS || 0);

const MODELS = [
  { id: 'openai/gpt-4o-mini',           ctx: 128000, prompt: '0.00000015', completion: '0.0000006' },
  { id: 'anthropic/claude-sonnet-4.5',  ctx: 200000, prompt: '0.000003',   completion: '0.000015' },
  { id: 'google/gemini-2.5-flash',      ctx: 1048576, prompt: '0.0000003', completion: '0.0000025' },
  { id: 'deepseek/deepseek-chat',       ctx: 65536,  prompt: '0.00000027', completion: '0.0000011' },
  { id: 'qwen/qwen3-32b',               ctx: 131072, prompt: '0.0000001',  completion: '0.0000003' },
];

const json = (res, code, obj) => {
  res.writeHead(code, { 'content-type': 'application/json' });
  res.end(JSON.stringify(obj));
};

const readBody = req => new Promise(r => {
  let b = '';
  req.on('data', c => (b += c));
  req.on('end', () => r(b ? JSON.parse(b) : {}));
});

http.createServer(async (req, res) => {
  const url = req.url.split('?')[0];

  // OpenAI 风格 + OpenRouter 风格模型列表（含定价/上下文，供 A4 同步用）
  if (req.method === 'GET' && (url === '/v1/models' || url === '/api/v1/models')) {
    return json(res, 200, {
      data: MODELS.map(m => ({
        id: m.id, object: 'model', name: m.id,
        context_length: m.ctx,
        pricing: { prompt: m.prompt, completion: m.completion },
        supported_parameters: ['temperature', 'top_p', 'max_tokens', 'tools', 'stream'],
      })),
    });
  }

  if (req.method === 'POST' && (url === '/v1/chat/completions' || url === '/api/v1/chat/completions')) {
    if (FAIL) return json(res, 500, { error: { message: 'mock upstream forced failure', type: 'server_error' } });
    const body = await readBody(req);
    const model = body.model || 'unknown';
    if (!MODELS.some(m => m.id === model)) {
      return json(res, 404, { error: { message: `model ${model} not found`, type: 'invalid_request_error' } });
    }
    const reply = `mock@${PORT} reply from ${model}`;
    const usage = { prompt_tokens: 12, completion_tokens: 8, total_tokens: 20 };
    const id = 'chatcmpl-mock' + PORT;

    if (body.stream) {
      res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache' });
      const chunk = delta => `data: ${JSON.stringify({ id, object: 'chat.completion.chunk', model, choices: [{ index: 0, delta, finish_reason: null }] })}\n\n`;
      setTimeout(() => {
        res.write(chunk({ role: 'assistant', content: '' }));
        for (const word of reply.split(' ')) res.write(chunk({ content: word + ' ' }));
        res.write(`data: ${JSON.stringify({ id, object: 'chat.completion.chunk', model, choices: [{ index: 0, delta: {}, finish_reason: 'stop' }], usage })}\n\n`);
        res.write('data: [DONE]\n\n');
        res.end();
      }, TTFT_MS);
      return;
    }
    return json(res, 200, {
      id, object: 'chat.completion', model,
      choices: [{ index: 0, message: { role: 'assistant', content: reply }, finish_reason: 'stop' }],
      usage,
    });
  }

  json(res, 404, { error: { message: `no route ${req.method} ${url}` } });
}).listen(PORT, () => console.log(`mock upstream on :${PORT} fail=${FAIL} ttft=${TTFT_MS}ms`));
