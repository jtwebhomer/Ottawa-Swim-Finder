/**
 * API key authentication — all routes require x-api-key header.
 */
export function createApiKeyMiddleware(apiKey) {
  if (!apiKey) {
    throw new Error('API_KEY must be set in .env');
  }

  const expected = apiKey.trim();

  return (req, res, next) => {
    if (req.method === 'OPTIONS') return next();

    const provided = (req.headers['x-api-key'] || '').trim();
    if (!provided || provided !== expected) {
      return res.status(401).json({ error: 'Unauthorized — invalid or missing x-api-key' });
    }
    next();
  };
}
