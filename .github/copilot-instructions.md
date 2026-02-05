# GitHub Copilot Instructions - Eventhound

## 🎯 Project Context

**Eventhound** is a cultural events aggregation platform based on **event-driven** architecture with microservices. The system uses intelligent web scraping to discover, classify, extract, and normalize event information from multiple web sources.

## 🏗️ Key Architecture

### Single Writer Principle ⚠️ CRITICAL
- **ONLY the Event Processor can write to the database**
- Workers (Discovery, Scraping, Classification, Extraction) only:
  - Read configuration from DB (if necessary)
  - Publish events to RabbitMQ
  - **NEVER** write directly to PostgreSQL

### Event-Driven Flow
```
API Gateway → Command → Worker → Event → Event Processor → Database
```

### 6 Microservices
1. **API Gateway** - REST API (Express)
2. **Discovery Worker** - Discovers URLs (Crawlee)
3. **Scraping Worker** - Fetches HTML (Crawlee)
4. **Classification Worker** - Classifies pages (rule-based)
5. **Extraction Worker** - Extracts structured data
6. **Event Processor** - Orchestrates flow and writes to DB (SINGLE WRITER)

## 📋 Code Conventions

### TypeScript
```typescript
// ✅ GOOD: Explicit types, descriptive names
async function handleDiscoveryCompleted(
  envelope: EnvelopeV1<DiscoveryUrlsFoundPayload>
): Promise<void> {
  const { source_id, urls } = envelope.payload;
  // ...
}

// ❌ BAD: Any types, generic names
async function handle(data: any): Promise<any> {
  // ...
}
```

### Naming
- **Variables/Functions:** `camelCase`
- **Classes:** `PascalCase`
- **Constants:** `UPPER_SNAKE_CASE`
- **Files:** `kebab-case.ts`
- **Message types:** `cmd.aggregate.action` or `evt.aggregate.past_participle`

### File Structure
```
services/[service-name]/
├── src/
│   ├── handlers/         # Message handlers
│   ├── services/         # Business logic
│   ├── repositories/     # DB operations (Event Processor only)
│   ├── strategies/       # Strategy pattern implementations
│   ├── utils/            # Utilities
│   ├── index.ts          # Entry point
│   └── config.ts         # Configuration
├── __tests__/            # Tests
├── Dockerfile
└── package.json
```

## 🔧 Technology Stack

### Core
- **Runtime:** Node.js 20+ with TypeScript 5
- **Database:** PostgreSQL 15+ (schema: `webscraping`)
- **Message Broker:** RabbitMQ 3.12+
- **Cache:** Redis 7
- **ORM:** Drizzle ORM
- **Scraping:** Crawlee (CheerioCrawler + PlaywrightCrawler)
- **Validation:** Zod

### Contracts
```typescript
// ✅ ALWAYS use @urbanmoop/contracts
import {
  type EnvelopeV1,
  MESSAGE_TYPES,
  buildSourceDiscoverCommand,
  validateMessage,
} from '@urbanmoop/contracts';

// ❌ NEVER create message schemas manually
```

## 📝 Required Patterns

### 1. Message Handlers
```typescript
// ✅ Correct pattern for handlers
export class DiscoveryHandler {
  constructor(
    private readonly broker: MessageBroker,
    private readonly redisCache: RedisCacheService
  ) {}

  async handleUrlsFound(
    envelope: EnvelopeV1<DiscoveryUrlsFoundPayload>
  ): Promise<void> {
    const { source_id, urls } = envelope.payload;

    logger.info('Processing discovered URLs', {
      source_id,
      url_count: urls.length,
      correlation_id: envelope.correlation_id,
    });

    // 1. Validate payload
    // 2. Process logic
    // 3. Publish resulting events
    // 4. Log result
  }
}
```

### 2. Publishing Events
```typescript
// ✅ Always use builders and maintain correlation/causation chain
const event = buildDiscoveryUrlsFoundEvent({
  source_id,
  urls,
  // ... payload
}, {
  correlation_id: envelope.correlation_id,
  causation_id: envelope.message_id,
});

await this.broker.publish('discovery.events', event);
```

### 3. Structured Logging
```typescript
// ✅ Logs with structured context
logger.info('Discovery completed', {
  source_id,
  total_urls: urls.length,
  correlation_id,
  duration_ms,
});

// ❌ Logs without context
console.log('Discovery done');
```

### 4. Error Handling
```typescript
// ✅ Proper error handling
try {
  await processData();
} catch (error) {
  logger.error('Processing failed', {
    error: error instanceof Error ? error.message : String(error),
    source_id,
    correlation_id,
  });

  // Publish error event
  await this.publishErrorEvent(envelope, error);
}
```

## 🚫 Anti-Patterns (AVOID)

### ❌ DO NOT in Workers
```typescript
// ❌ NEVER: Workers writing to DB
await db.insert(pages).values({ ... }); // Event Processor only!

// ❌ NEVER: Expose Crawlee details in contracts
const event = {
  crawlee_request_id: request.id, // Implementation detail
  // ...
};
```

### ❌ DO NOT Create Non-Agnostic Contracts
```typescript
// ❌ BAD: Contract exposes implementation
interface ScrapeCommand {
  crawlee_config: CrawleeOptions; // No!
}

// ✅ GOOD: Agnostic contract
interface ScrapeCommand {
  requires_javascript: boolean;
  timeout_ms?: number;
}
```

## 🧪 Testing

### Test Structure
```typescript
// ✅ Descriptive tests with AAA pattern
describe('DiscoveryHandler', () => {
  describe('handleUrlsFound', () => {
    it('should insert new pages and publish scrape commands', async () => {
      // Arrange
      const envelope = buildTestEnvelope();
      const handler = new DiscoveryHandler(mockBroker, mockRedis);

      // Act
      await handler.handleUrlsFound(envelope);

      // Assert
      expect(mockBroker.publish).toHaveBeenCalledWith(
        'scrape.commands',
        expect.objectContaining({
          message_type: MESSAGE_TYPES.CMD_SCRAPE_PAGE_REQUESTED,
        })
      );
    });
  });
});
```

## 🔐 Security

### Environment Variables
```typescript
// ✅ Validate environment variables
const config = {
  database: {
    url: process.env.DATABASE_URL || throwError('DATABASE_URL required'),
  },
};

// ❌ Don't hardcode secrets
const password = 'mysecret123'; // No!
```

### SQL Injection
```typescript
// ✅ Use Drizzle ORM (automatically protects)
await db.select().from(pages).where(eq(pages.id, pageId));

// ❌ Don't build SQL manually
await db.execute(`SELECT * FROM pages WHERE id = ${pageId}`); // No!
```

## 📚 Key References

- **Architecture:** [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md)
- **Contracts:** [docs/CONTRACTS.md](../docs/CONTRACTS.md)
- **Migrations:** [docs/MIGRATIONS.md](../docs/MIGRATIONS.md)
- **Plan:** [docs/PLAN.md](../docs/PLAN.md)

## 🎨 Format and Style

```bash
# Run before commit
npm run lint        # ESLint
npm run format      # Prettier
npm run typecheck   # TypeScript
npm test            # Tests
```

## 💡 Tips for Copilot

1. **Prioritize event-driven architecture** - Always think in terms of commands and events
2. **Respect Single Writer** - If you need to write to DB, do it from Event Processor
3. **Use existing contracts** - Don't reinvent, use `@urbanmoop/contracts`
4. **Structured logging** - Always include `correlation_id` in logs
5. **Tests first** - Think about testability from design
6. **Exhaustive error handling** - Handle all failure cases
7. **Document decisions** - Comment the "why", not just the "what"

## 🔄 Typical Development Flow

1. **Read issue** on GitHub with acceptance criteria
2. **Implement handler/service** respecting architecture
3. **Use builders** from `@urbanmoop/contracts` for messages
4. **Write tests** (unit + integration)
5. **Verify lint/typecheck** passes
6. **Create PR** with complete template
7. **Wait for review** and CI/CD to pass

## Git & PR Workflow

### Branch Naming

```bash
# Features/bugs (ALWAYS include issue number):
feature/issue-N-descripción-corta
# Example: feature/issue-2-add-linting-formatting

# Docs (no issue required):
docs/descripción-corta

# Chores (no issue required):
chore/descripción-corta
```

### Merge Strategy

- **Features/Issues:** Use `Merge commit` (preserve full history, easy revert)
- **Hotfixes/Typos:** Use `Squash and merge` (clean linear history)
- **NEVER:** Push directly to main - always create PR
- **PR Title:** Must match branch name
- **Closing:** Use `Closes #N` in PR description for auto-close

See full conventions in [docs/CONVENTIONS.md](../docs/CONVENTIONS.md).

Check [docs/CONVENTIONS.md](../docs/CONVENTIONS.md#labels-establecidos) for label system (`area:*`, `prio:*`, `type:*`).

---

**Remember:** This is an event-driven system. Always think in terms of **asynchronous messages**, **single writer**, and **agnostic contracts**. 🚀
