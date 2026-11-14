const json = { 'application/json': { schema: { type: 'object', additionalProperties: true } } };
const accountParameter = {
  name: 'accountId', in: 'path', required: true,
  schema: { type: 'string' }, description: 'Quantivita account identifier.',
};

const operation = (summary, { auth = true, parameters = [], requestBody, responses } = {}) => ({
  summary,
  ...(auth ? { security: [{ bearerAuth: [] }] } : {}),
  ...(parameters.length ? { parameters } : {}),
  ...(requestBody ? { requestBody: { required: true, content: { 'application/json': { schema: requestBody } } } } : {}),
  responses: responses || { 200: { description: 'Successful response', content: json } },
});

export function openapiDocument(baseUrl) {
  return {
    openapi: '3.1.0',
    info: {
      title: 'Quantivita API',
      version: '0.2.0',
      description: 'REST and MCP endpoints for syncing and retrieving Quantivita health data.',
    },
    servers: [{ url: baseUrl }],
    tags: [
      { name: 'System' }, { name: 'Accounts' }, { name: 'Health' },
      { name: 'Workouts' }, { name: 'Progressa' }, { name: 'Strava' }, { name: 'MCP' },
    ],
    paths: {
      '/healthz': { get: { ...operation('Health check', { auth: false }), tags: ['System'] } },
      '/mcp': {
        post: { ...operation('Send an MCP JSON-RPC request'), tags: ['MCP'] },
        get: { ...operation('Open an MCP stream'), tags: ['MCP'] },
        delete: { ...operation('Close an MCP session'), tags: ['MCP'] },
      },
      '/api/auth/config': { get: { ...operation('Get public authentication configuration', { auth: false }), tags: ['Accounts'] } },
      '/api/me/session': { get: { ...operation('Get the browser session', { auth: false }), tags: ['Accounts'] } },
      '/api/logout': { post: { ...operation('Clear the browser session', { auth: false }), tags: ['Accounts'] } },
      '/api/accounts/register': {
        post: {
          ...operation('Register or refresh a native account', {
            auth: false,
            requestBody: {
              type: 'object', required: ['accountId', 'syncToken'],
              properties: {
                accountId: { type: 'string' }, syncToken: { type: 'string', writeOnly: true },
                appleLinked: { type: 'boolean' },
              },
            },
            responses: { 202: { description: 'Account registered', content: json }, 409: { description: 'Token conflict', content: json } },
          }),
          tags: ['Accounts'],
        },
      },
      '/api/accounts/login': {
        post: {
          ...operation('Create a browser session', {
            auth: false,
            requestBody: {
              type: 'object', required: ['accountId', 'syncToken'],
              properties: { accountId: { type: 'string' }, syncToken: { type: 'string', writeOnly: true } },
            },
          }),
          tags: ['Accounts'],
        },
      },
      '/api/users/{accountId}': {
        delete: { ...operation('Delete an account and its data', { parameters: [accountParameter], responses: { 204: { description: 'Deleted' } } }), tags: ['Accounts'] },
      },
      '/api/users/{accountId}/health': {
        get: { ...operation('Get all stored health data', { parameters: [accountParameter] }), tags: ['Health'] },
      },
      '/api/users/{accountId}/summary': {
        get: { ...operation('Get a health summary', { parameters: [accountParameter] }), tags: ['Health'] },
      },
      '/api/users/{accountId}/health/debug/daily': {
        get: {
          ...operation('Get scoring diagnostics for a day', {
            parameters: [accountParameter, { name: 'date', in: 'query', schema: { type: 'string', format: 'date' } }],
          }),
          tags: ['Health'],
        },
      },
      '/api/users/{accountId}/workouts': {
        get: {
          ...operation('Get workouts (last 30 days by default)', {
            parameters: [
              accountParameter,
              { name: 'from', in: 'query', schema: { type: 'string', format: 'date-time' } },
              { name: 'to', in: 'query', schema: { type: 'string', format: 'date-time' } },
              { name: 'all', in: 'query', schema: { type: 'boolean', default: false } },
            ],
            responses: { 200: { description: 'Workout list', content: { 'application/json': { schema: { type: 'array', items: { $ref: '#/components/schemas/Workout' } } } } } },
          }),
          tags: ['Workouts'],
        },
      },
      '/api/users/{accountId}/workout-merges': {
        get: { ...operation('Get canonical combinations and hidden source IDs', { parameters: [accountParameter] }), tags: ['Workouts'] },
        post: { ...operation('Confirm an in-app combination (idempotent)', { parameters: [accountParameter], requestBody: { $ref: '#/components/schemas/MergeRequest' } }), tags: ['Workouts'] },
      },
      '/api/users/{accountId}/workout-merges/preview': {
        post: { ...operation('Preview totals, sources and overlap before combining', { parameters: [accountParameter], requestBody: { $ref: '#/components/schemas/MergeRequest' } }), tags: ['Workouts'] },
      },
      '/api/users/{accountId}/workout-merges/{mergeId}/undo': {
        post: { ...operation('Restore original activities (idempotent)', { parameters: [accountParameter, {name: 'mergeId', in: 'path', required: true, schema: {type: 'string'}}] }), tags: ['Workouts'] },
      },
      '/api/users/{accountId}/ingest': {
        post: {
          ...operation('Ingest health data and workouts', {
            parameters: [accountParameter], requestBody: { $ref: '#/components/schemas/IngestRequest' },
            responses: { 202: { description: 'Data accepted', content: json } },
          }),
          tags: ['Health'],
        },
      },
      '/api/users/{accountId}/export.csv': {
        get: { ...operation('Export account data as CSV', { parameters: [accountParameter] }), tags: ['Health'] },
      },
      '/api/users/{accountId}/integrations/progressa': {
        get: { ...operation('Get Progressa connection status', { parameters: [accountParameter] }), tags: ['Progressa'] },
        delete: { ...operation('Disconnect Progressa', { parameters: [accountParameter] }), tags: ['Progressa'] },
      },
      '/api/users/{accountId}/integrations/progressa/connect': {
        post: { ...operation('Connect Progressa with tokens', { parameters: [accountParameter], requestBody: { type: 'object', additionalProperties: true } }), tags: ['Progressa'] },
      },
      '/api/users/{accountId}/integrations/progressa/exchange': {
        post: { ...operation('Exchange a Progressa authorization code', { parameters: [accountParameter], requestBody: { type: 'object', required: ['code'], properties: { code: { type: 'string' } } } }), tags: ['Progressa'] },
      },
      '/api/users/{accountId}/integrations/progressa/workouts': {
        get: { ...operation('Sync linked Progressa workouts', { parameters: [accountParameter] }), tags: ['Progressa', 'Workouts'] },
      },
      '/api/users/{accountId}/integrations/strava': {
        get: { ...operation('Get Strava connection status', { parameters: [accountParameter] }), tags: ['Strava'] },
        delete: { ...operation('Disconnect Strava', { parameters: [accountParameter] }), tags: ['Strava'] },
      },
      '/api/users/{accountId}/integrations/strava/authorize-url': {
        get: { ...operation('Create a Strava authorization URL', { parameters: [accountParameter, { name: 'state', in: 'query', required: true, schema: { type: 'string' } }] }), tags: ['Strava'] },
      },
      '/api/users/{accountId}/integrations/strava/exchange': {
        post: { ...operation('Exchange a Strava authorization code', { parameters: [accountParameter], requestBody: { type: 'object', additionalProperties: true } }), tags: ['Strava'] },
      },
      '/api/users/{accountId}/integrations/strava/upload': {
        post: { ...operation('Upload a TCX workout to Strava', { parameters: [accountParameter], requestBody: { type: 'object', additionalProperties: true } }), tags: ['Strava', 'Workouts'] },
      },
      '/api/users/{accountId}/integrations/strava/uploads/{uploadId}': {
        get: {
          ...operation('Get Strava upload status', {
            parameters: [accountParameter, { name: 'uploadId', in: 'path', required: true, schema: { type: 'string' } }],
          }),
          tags: ['Strava'],
        },
      },
    },
    components: {
      securitySchemes: { bearerAuth: { type: 'http', scheme: 'bearer' } },
      schemas: {
        MergeRequest: { type: 'object', required: ['workoutIds'], properties: {
          workoutIds: {type: 'array', minItems: 2, maxItems: 100, uniqueItems: true, items: {type: 'string'}},
          strategy: {type: 'string', enum: ['concatenate','time_only','duplicate'], default: 'concatenate', description: 'duplicate keeps the first selected source; time_only leaves overlapping distance, energy and averages unknown.'},
        } },
        Workout: {
          type: 'object', required: ['id', 'title', 'startTime'],
          properties: {
            id: { type: 'string' }, source: { type: 'string' }, title: { type: 'string' },
            startTime: { type: 'string', format: 'date-time' }, durationMinutes: { type: 'number' },
            energyKcal: { type: ['number', 'null'] }, distanceMeters: { type: ['number', 'null'] },
            avgPowerWatts: {type: ['number','null']}, maxPowerWatts: {type: ['number','null']}, normalizedPowerWatts: {type: ['number','null']},
            avgCadenceRpm: {type: ['number','null']}, maxCadenceRpm: {type: ['number','null']},
            averageHeartRate: {type: ['number','null']}, maxHeartRate: {type: ['number','null']},
            provider: {type: ['string','null']}, importedVia: {type: ['string','null']}, externalWorkoutId: {type: ['string','null']},
            merge: {type: ['object','null'], additionalProperties: true},
          },
          additionalProperties: true,
        },
        IngestRequest: {
          type: 'object', required: ['workouts'],
          properties: {
            profile: { type: 'object', additionalProperties: true },
            daily: { type: 'array', items: { type: 'object', additionalProperties: true } },
            workouts: { type: 'array', items: { $ref: '#/components/schemas/Workout' } },
          },
        },
      },
    },
  };
}

export function swaggerHtml() {
  return `<!doctype html><html><head><meta charset="utf-8"><title>Quantivita API docs</title>
<link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5.17.14/swagger-ui.css"></head>
<body><div id="swagger-ui"></div><script src="https://unpkg.com/swagger-ui-dist@5.17.14/swagger-ui-bundle.js"></script>
<script>SwaggerUIBundle({url:'/openapi.json',dom_id:'#swagger-ui',deepLinking:true,persistAuthorization:true});</script></body></html>`;
}
