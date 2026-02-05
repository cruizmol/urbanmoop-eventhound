# Plan de Desarrollo Completo - Eventhound

## Resumen Ejecutivo

**Objetivo:** Implementar la plataforma completa de agregación de eventos Eventhound según la arquitectura event-driven documentada en [ARCHITECTURE.md](../../../Users/cruiz/DevProjects/UrbanMoop/eventhound/docs/ARCHITECTURE.md).

**Estado Actual:**
- ✅ Documentación completa (ARCHITECTURE.md, MIGRATIONS.md, CONTRACTS.md)
- ✅ Migraciones SQL base (1-5 de 8)
- ❌ Contratos de mensajería: 7/20 implementados (35%)
- ❌ Servicios: 0/6 implementados (0%)
- ❌ Infraestructura: No existe

**Alcance:** Implementación completa production-ready con:
- 6 microservicios (API Gateway, 4 workers, Event Processor)
- Discovery multi-estrategia (sitemap, link crawl, RSS, patterns)
- Sistema de deduplicación con Redis
- Testing completo (unitarios + integración + E2E)
- CI/CD con GitHub Actions
- Infraestructura Docker/Kubernetes

---

## Arquitectura de Fases

El plan se divide en **5 fases secuenciales** con entregables verificables:

```
FASE 1: Contratos y Base de Datos (2-3 semanas)
  ├─ Implementar 13 contratos faltantes en urbanmoop-contracts
  ├─ Ejecutar migraciones 006, 007, 008 en PostgreSQL
  └─ Configurar infraestructura base (Docker, RabbitMQ, Redis)

FASE 2: Event Processor y Shared Packages (2 semanas)
  ├─ Crear paquete shared con tipos y utilidades
  ├─ Implementar Event Processor (single writer)
  └─ Configurar message broker y persistencia

FASE 3: Discovery y Scraping Workers (3 semanas)
  ├─ Implementar Discovery Worker con 4 estrategias
  ├─ Implementar Scraping Worker (Crawlee HTTP + Browser)
  └─ Sistema de deduplicación con Redis

FASE 4: Classification y Extraction Workers (2 semanas)
  ├─ Implementar Classification Worker (rule-based)
  ├─ Implementar Extraction Worker (parsing multi-template)
  └─ Flujo end-to-end completo

FASE 5: API Gateway, Testing y Producción (2-3 semanas)
  ├─ Implementar API Gateway (REST)
  ├─ Tests completos (unit + integration + E2E)
  ├─ CI/CD (GitHub Actions)
  └─ Deployment (Docker Compose en VPS + monitoring)
```

**Duración Total Estimada:** 11-13 semanas

---

## FASE 1: Contratos y Base de Datos

### 1.1 Implementar Contratos Faltantes en urbanmoop-contracts

**Objetivo:** Completar los 13 contratos faltantes siguiendo el patrón establecido.

#### Estructura de archivos a crear:

```
urbanmoop-contracts/src/messages/
├── classify/
│   ├── index.ts          # Schemas Zod + auto-registro
│   ├── builders.ts       # buildPageClassifyCommand, buildPageClassifiedEventEvent, etc.
│   └── types.ts          # Interfaces TypeScript
├── extract/
│   ├── index.ts          # Schemas para extraction (cmd.event.extract + 3 eventos)
│   ├── builders.ts       # buildEventExtractCommand, buildEventExtractedEvent, etc.
│   └── types.ts          # ExtractedEventData, LocationSchema, PriceSchema, etc.
├── event/
│   ├── index.ts          # Schemas para persistencia (evt.event.created/updated)
│   ├── builders.ts       # buildEventCreatedEvent, buildEventUpdatedEvent
│   └── types.ts          # Interfaces
└── discovery/
    ├── index.ts          # Schemas para discovery (1 cmd + 3 eventos)
    ├── builders.ts       # buildSourceDiscoverCommand, buildDiscoveryUrlsFoundEvent, etc.
    └── types.ts          # DiscoveryStrategy enum, payloads
```

#### Contratos a implementar:

**Classification (3 contratos):**
- `cmd.page.classify` - Solicitar clasificación
- `evt.page.classified.event` - Clasificado como evento
- `evt.page.classified.other` - Clasificado como no-evento

**Extraction (4 contratos):**
- `cmd.event.extract` - Solicitar extracción
- `evt.event.extracted` - Datos extraídos
- `evt.event.duplicate` - Evento duplicado
- `evt.event.extraction_failed` - Extracción fallida

**Event Persistence (2 contratos):**
- `evt.event.created` - Evento persistido
- `evt.event.updated` - Evento actualizado

**Discovery (4 contratos):**
- `cmd.source.discover` - Iniciar descubrimiento
- `evt.discovery.urls_found` - URLs descubiertas (batch)
- `evt.discovery.completed` - Descubrimiento completado
- `evt.discovery.failed` - Descubrimiento fallido

#### Pasos de implementación:

1. **Crear archivos base** siguiendo el patrón de `messages/pages/`:
   ```bash
   mkdir -p src/messages/{classify,extract,event,discovery}
   touch src/messages/classify/{index,builders,types}.ts
   touch src/messages/extract/{index,builders,types}.ts
   touch src/messages/event/{index,builders,types}.ts
   touch src/messages/discovery/{index,builders,types}.ts
   ```

2. **Implementar schemas Zod** (copiar desde [CONTRACTS.md](../../../Users/cruiz/DevProjects/UrbanMoop/eventhound/docs/CONTRACTS.md) líneas 206-1260):
   - Usar `.extend()` de EnvelopeSchemaV1
   - Registrar automáticamente con `registry.register()`
   - Exportar tipos TypeScript con `z.infer<>`

3. **Implementar builders** siguiendo el patrón:
   ```typescript
   export function buildPageClassifyCommand(
     payload: PageClassifyPayload,
     options?: { correlation_id?: string; causation_id?: string }
   ): EnvelopeV1<PageClassifyPayload> {
     return {
       message_id: uuidv4(),
       message_type: 'cmd.page.classify',
       schema_version: 1,
       occurred_at: new Date().toISOString(),
       correlation_id: options?.correlation_id ?? uuidv4(),
       causation_id: options?.causation_id,
       tenant_id: payload.tenant_id,
       aggregate: { type: 'page', id: payload.page_id },
       payload,
     };
   }
   ```

4. **Actualizar MESSAGE_TYPES** en `src/messages/constants.ts`:
   ```typescript
   export const MESSAGE_TYPES = {
     // ... existentes
     CMD_PAGE_CLASSIFY: 'cmd.page.classify',
     EVT_PAGE_CLASSIFIED_EVENT: 'evt.page.classified.event',
     EVT_PAGE_CLASSIFIED_OTHER: 'evt.page.classified.other',
     CMD_EVENT_EXTRACT: 'cmd.event.extract',
     // ... todos los nuevos
   } as const;
   ```

5. **Exportar desde index.ts principal**:
   ```typescript
   export * from './messages/classify';
   export * from './messages/extract';
   export * from './messages/event';
   export * from './messages/discovery';
   ```

6. **Tests unitarios** para cada contrato:
   ```typescript
   // tests/messages/classify/PageClassify.test.ts
   describe('PageClassify', () => {
     it('validates correct payload', () => {
       const payload = { page_id: uuidv4(), url: 'https://...', ... };
       expect(() => PageClassifyPayloadSchema.parse(payload)).not.toThrow();
     });

     it('rejects invalid payload', () => {
       const invalid = { page_id: 'not-a-uuid', ... };
       expect(() => PageClassifyPayloadSchema.parse(invalid)).toThrow();
     });

     it('builder generates valid envelope', () => {
       const msg = buildPageClassifyCommand({ ... });
       expect(msg.message_id).toBeDefined();
       expect(msg.correlation_id).toBeDefined();
       expect(msg.message_type).toBe('cmd.page.classify');
     });
   });
   ```

7. **Publicar versión nueva**:
   ```bash
   npm version minor  # 0.x.0 -> 0.y.0
   npm publish
   ```

---

### 1.2 Ejecutar Migraciones SQL Faltantes

**Objetivo:** Completar el schema de BD con tracking, clasificación y discovery.

#### Migraciones pendientes:

**006_add_processing_tracking.sql** (crear archivo):
- Copiar código SQL completo desde [MIGRATIONS.md](../../../Users/cruiz/DevProjects/UrbanMoop/eventhound/docs/MIGRATIONS.md) líneas 151-455
- Crea: `page_statuses`, `page_processing_history`, `page_status_transitions`
- Añade campos a `pages`: `correlation_id`, `last_message_id`, `processing_started_at`, `scrape_completed_at`, etc.

**007_add_classification_fields.sql** (crear archivo):
- Copiar desde MIGRATIONS.md líneas 463-766
- Crea: `classification_rules`, `duplicate_events`
- Añade a `pages`: `is_event`, `classification_score`, `classification_method`
- Añade a `events`: `page_id`, `correlation_id`, `data_quality_score`

**008_add_discovery_tracking.sql** (crear archivo):
- Copiar desde MIGRATIONS.md líneas 774-1076
- Crea: `discovery_runs`, `discovered_urls`, `discovery_schedules`
- Añade a `pages`: `discovered_by`, `discovery_run_id`
- Añade a `source_configurations`: `discovery_config` (JSONB)

#### Pasos:

1. **Crear archivos SQL**:
   ```bash
   cd migrations/
   touch 006_add_processing_tracking.sql
   touch 007_add_classification_fields.sql
   touch 008_add_discovery_tracking.sql
   ```

2. **Copiar código SQL** desde MIGRATIONS.md (ya está completo en la documentación)

3. **Ejecutar migraciones en orden**:
   ```bash
   # Configurar DATABASE_URL
   export DATABASE_URL="postgresql://eventhound:secret@localhost:5432/eventhound"

   # Ejecutar migraciones
   psql $DATABASE_URL -f migrations/006_add_processing_tracking.sql
   psql $DATABASE_URL -f migrations/007_add_classification_fields.sql
   psql $DATABASE_URL -f migrations/008_add_discovery_tracking.sql
   ```

4. **Verificar con script**:
   ```bash
   psql $DATABASE_URL -f migrations/verify_sequence_permissions.sql
   ```

5. **Crear scripts de rollback** (008, 007, 006):
   ```bash
   touch migrations/rollback_008.sql
   touch migrations/rollback_007.sql
   touch migrations/rollback_006.sql
   ```

---

### 1.3 Configurar Infraestructura Base

**Objetivo:** Levantar PostgreSQL, RabbitMQ, Redis con Docker Compose.

#### Archivos a crear:

**docker/docker-compose.dev.yml:**
```yaml
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: eventhound-postgres
    environment:
      POSTGRES_DB: eventhound
      POSTGRES_USER: eventhound
      POSTGRES_PASSWORD: eventhound_dev
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ../migrations:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U eventhound"]
      interval: 10s
      timeout: 5s
      retries: 5

  rabbitmq:
    image: rabbitmq:3.12-management-alpine
    container_name: eventhound-rabbitmq
    environment:
      RABBITMQ_DEFAULT_USER: eventhound
      RABBITMQ_DEFAULT_PASS: eventhound_dev
    ports:
      - "5672:5672"   # AMQP
      - "15672:15672" # Management UI
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: eventhound-redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
  rabbitmq_data:
  redis_data:
```

**package.json raíz:**
```json
{
  "name": "eventhound",
  "version": "0.1.0",
  "private": true,
  "workspaces": [
    "packages/*",
    "services/*"
  ],
  "scripts": {
    "dev:infra": "docker-compose -f docker/docker-compose.dev.yml up -d",
    "dev:infra:down": "docker-compose -f docker/docker-compose.dev.yml down",
    "dev:logs": "docker-compose -f docker/docker-compose.dev.yml logs -f",
    "db:migrate": "psql $DATABASE_URL -f migrations/001_create_schema_and_basic_tables.sql && ...",
    "lint": "eslint . --ext .ts,.tsx",
    "format": "prettier --write .",
    "typecheck": "tsc --noEmit"
  },
  "devDependencies": {
    "@types/node": "^20.11.0",
    "@typescript-eslint/eslint-plugin": "^6.19.0",
    "@typescript-eslint/parser": "^6.19.0",
    "eslint": "^8.56.0",
    "prettier": "^3.2.4",
    "typescript": "^5.3.3"
  }
}
```

**tsconfig.json raíz:**
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "moduleResolution": "node",
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "paths": {
      "@eventhound/shared": ["./packages/shared/src"],
      "@eventhound/shared/*": ["./packages/shared/src/*"]
    }
  },
  "exclude": ["node_modules", "dist"]
}
```

**.env.example:**
```bash
# Database
DATABASE_URL=postgresql://eventhound:eventhound_dev@localhost:5432/eventhound
DATABASE_SCHEMA=webscraping

# Message Broker
RABBITMQ_URL=amqp://eventhound:eventhound_dev@localhost:5672
RABBITMQ_EXCHANGE=eventhound

# Redis
REDIS_URL=redis://localhost:6379

# Crawlee
CRAWLEE_STORAGE_DIR=/tmp/crawlee
CRAWLEE_PERSIST_STORAGE=false

# Logging
LOG_LEVEL=info
LOG_FORMAT=json

# Tenant
DEFAULT_TENANT_ID=default
```

#### Verificación Fase 1:

```bash
# 1. Levantar infraestructura
npm run dev:infra

# 2. Verificar servicios
docker ps  # Debe mostrar postgres, rabbitmq, redis healthy

# 3. Verificar BD
psql $DATABASE_URL -c "\dt webscraping.*"  # Debe mostrar ~30 tablas

# 4. Verificar RabbitMQ Management
open http://localhost:15672  # Login: eventhound/eventhound_dev

# 5. Verificar contratos publicados
npm list @urbanmoop/contracts  # Debe mostrar versión nueva
```

---

## FASE 2: Event Processor y Shared Packages

### 2.1 Crear Paquete Shared

**Objetivo:** Código compartido entre todos los servicios.

#### Estructura:

```
packages/shared/
├── src/
│   ├── types/
│   │   ├── database.ts       # Tipos de BD (Drizzle ORM)
│   │   ├── config.ts         # Configuración compartida
│   │   └── index.ts
│   ├── utils/
│   │   ├── logger.ts         # Winston logger
│   │   ├── hash.ts           # SHA256 utils
│   │   ├── validation.ts     # Helpers de validación
│   │   └── index.ts
│   ├── messaging/
│   │   ├── broker.ts         # RabbitMQ client abstracto
│   │   ├── publisher.ts      # Publicar eventos
│   │   ├── consumer.ts       # Consumir mensajes
│   │   └── index.ts
│   ├── database/
│   │   ├── connection.ts     # Pool de conexiones
│   │   ├── schema.ts         # Drizzle schemas (todas las tablas)
│   │   └── index.ts
│   └── index.ts
├── package.json
└── tsconfig.json
```

#### Archivos clave:

**packages/shared/src/messaging/broker.ts:**
```typescript
import amqp, { Connection, Channel } from 'amqplib';
import { EnvelopeV1 } from '@urbanmoop/contracts';
import { logger } from '../utils/logger';

export class MessageBroker {
  private connection?: Connection;
  private channel?: Channel;

  constructor(
    private readonly config: {
      url: string;
      exchange: string;
      exchangeType?: string;
    }
  ) {}

  async connect(): Promise<void> {
    this.connection = await amqp.connect(this.config.url);
    this.channel = await this.connection.createChannel();

    await this.channel.assertExchange(
      this.config.exchange,
      this.config.exchangeType ?? 'topic',
      { durable: true }
    );

    logger.info('MessageBroker connected', { exchange: this.config.exchange });
  }

  async publish(routingKey: string, message: EnvelopeV1): Promise<void> {
    if (!this.channel) throw new Error('Not connected');

    const buffer = Buffer.from(JSON.stringify(message));

    this.channel.publish(
      this.config.exchange,
      routingKey,
      buffer,
      {
        persistent: true,
        contentType: 'application/json',
        messageId: message.message_id,
        correlationId: message.correlation_id,
      }
    );

    logger.debug('Message published', {
      routingKey,
      messageId: message.message_id,
      messageType: message.message_type,
    });
  }

  async consume(
    queueName: string,
    routingKeys: string[],
    handler: (message: EnvelopeV1) => Promise<void>
  ): Promise<void> {
    if (!this.channel) throw new Error('Not connected');

    await this.channel.assertQueue(queueName, { durable: true });

    for (const routingKey of routingKeys) {
      await this.channel.bindQueue(queueName, this.config.exchange, routingKey);
    }

    this.channel.consume(queueName, async (msg) => {
      if (!msg) return;

      try {
        const envelope = JSON.parse(msg.content.toString()) as EnvelopeV1;
        await handler(envelope);
        this.channel!.ack(msg);
      } catch (error) {
        logger.error('Error processing message', { error, queueName });
        this.channel!.nack(msg, false, false); // Dead letter queue
      }
    });

    logger.info('Consumer started', { queueName, routingKeys });
  }

  async close(): Promise<void> {
    await this.channel?.close();
    await this.connection?.close();
  }
}
```

**packages/shared/src/database/schema.ts** (ejemplo):
```typescript
import { pgTable, serial, varchar, integer, timestamp, boolean, text, jsonb, real, uuid } from 'drizzle-orm/pg-core';

export const sources = pgTable('sources', {
  id: serial('id').primaryKey(),
  name: varchar('name', { length: 255 }).notNull(),
  base_url: text('base_url').notNull(),
  status: varchar('status', { length: 50 }).notNull(),
  created_at: timestamp('created_at').defaultNow(),
  updated_at: timestamp('updated_at').defaultNow(),
});

export const pages = pgTable('pages', {
  id: serial('id').primaryKey(),
  source_id: integer('source_id').references(() => sources.id).notNull(),
  url: text('url').notNull(),
  url_hash: varchar('url_hash', { length: 64 }).notNull(),
  status: varchar('status', { length: 50 }).notNull(),

  // Tracking fields (from migration 006)
  correlation_id: uuid('correlation_id'),
  last_message_id: uuid('last_message_id'),
  processing_started_at: timestamp('processing_started_at'),
  scrape_completed_at: timestamp('scrape_completed_at'),

  // Classification fields (from migration 007)
  is_event: boolean('is_event'),
  classification_score: real('classification_score'),
  classification_method: varchar('classification_method', { length: 50 }),

  // Discovery fields (from migration 008)
  discovered_by: varchar('discovered_by', { length: 50 }),

  html: text('html'),
  created_at: timestamp('created_at').defaultNow(),
  updated_at: timestamp('updated_at').defaultNow(),
});

export const events = pgTable('events', {
  id: serial('id').primaryKey(),
  source_id: integer('source_id').references(() => sources.id).notNull(),
  page_id: integer('page_id').references(() => pages.id),

  title: varchar('title', { length: 500 }).notNull(),
  description: text('description'),
  starts_at: timestamp('starts_at').notNull(),
  ends_at: timestamp('ends_at'),

  venue_id: integer('venue_id'),
  organizer_id: integer('organizer_id'),

  url: text('url').notNull(),
  image_url: text('image_url'),

  // Tracking
  correlation_id: uuid('correlation_id'),
  data_quality_score: real('data_quality_score'),

  created_at: timestamp('created_at').defaultNow(),
  updated_at: timestamp('updated_at').defaultNow(),
});

// ... resto de tablas (discovery_runs, page_processing_history, etc.)
```

---

### 2.2 Implementar Event Processor

**Objetivo:** Servicio central que orquesta el flujo y es el **único que escribe en BD**.

#### Estructura:

```
services/event-processor/
├── src/
│   ├── handlers/
│   │   ├── discovery.handler.ts     # Maneja evt.discovery.urls_found
│   │   ├── scrape.handler.ts        # Maneja evt.scrape.page.completed/failed
│   │   ├── classify.handler.ts      # Maneja evt.page.classified.*
│   │   ├── extract.handler.ts       # Maneja evt.event.extracted/duplicate/failed
│   │   └── index.ts
│   ├── repositories/
│   │   ├── pages.repository.ts      # Operaciones sobre pages
│   │   ├── events.repository.ts     # Operaciones sobre events
│   │   ├── discovery.repository.ts  # Operaciones sobre discovery_runs
│   │   └── index.ts
│   ├── services/
│   │   ├── orchestrator.service.ts  # Lógica de orquestación
│   │   ├── redis-cache.service.ts   # Sincronización Redis ↔ PostgreSQL
│   │   └── index.ts
│   ├── index.ts                      # Entry point
│   └── config.ts
├── Dockerfile
├── package.json
└── tsconfig.json
```

#### Ejemplo de handler:

**services/event-processor/src/handlers/discovery.handler.ts:**
```typescript
import { EnvelopeV1 } from '@urbanmoop/contracts';
import { DiscoveryUrlsFoundPayload, buildScrapePageRequestedCommand } from '@urbanmoop/contracts';
import { MessageBroker } from '@eventhound/shared/messaging';
import { db, pages, discovered_urls } from '@eventhound/shared/database';
import { RedisCacheService } from '../services/redis-cache.service';
import { sha256 } from '@eventhound/shared/utils';
import { logger } from '@eventhound/shared/utils';

export class DiscoveryHandler {
  constructor(
    private readonly broker: MessageBroker,
    private readonly redisCache: RedisCacheService
  ) {}

  async handleUrlsFound(envelope: EnvelopeV1<DiscoveryUrlsFoundPayload>): Promise<void> {
    const { source_id, discovery_run_id, urls } = envelope.payload;

    logger.info('Processing discovered URLs', {
      source_id,
      discovery_run_id,
      url_count: urls.length,
      correlation_id: envelope.correlation_id,
    });

    // 1. Insertar en BD (pages table)
    const newPages: Array<{ id: number; url: string }> = [];

    for (const url of urls) {
      const url_hash = sha256(url.url);

      try {
        const [page] = await db.insert(pages).values({
          source_id,
          url: url.url,
          url_hash,
          status: 'pending',
          discovered_by: envelope.payload.discovered_from.type,
          discovery_run_id,
          correlation_id: envelope.correlation_id,
        }).returning({ id: pages.id, url: pages.url });

        newPages.push(page);
      } catch (error: any) {
        // Conflict (duplicate) - skip
        if (error.code === '23505') {
          logger.debug('Duplicate URL skipped', { url: url.url, url_hash });
          continue;
        }
        throw error;
      }
    }

    // 2. Actualizar Redis cache (sincronizar)
    await this.redisCache.addUrlsToCache(
      source_id,
      urls.map(u => sha256(u.url))
    );

    // 3. Publicar comando de scraping para cada URL nueva
    for (const page of newPages) {
      const scrapeCmd = buildScrapePageRequestedCommand({
        page_id: String(page.id),
        url: page.url,
        tenant_id: envelope.tenant_id,
        scrape_config: {
          requires_javascript: false, // Default, puede venir de source_config
        },
      }, {
        correlation_id: envelope.correlation_id,
        causation_id: envelope.message_id,
      });

      await this.broker.publish('scrape.commands', scrapeCmd);
    }

    logger.info('URLs processed and scraping enqueued', {
      source_id,
      new_pages: newPages.length,
      skipped: urls.length - newPages.length,
    });
  }
}
```

**services/event-processor/src/index.ts:**
```typescript
import { MessageBroker } from '@eventhound/shared/messaging';
import { validateMessage, MESSAGE_TYPES } from '@urbanmoop/contracts';
import { DiscoveryHandler } from './handlers/discovery.handler';
import { ScrapeHandler } from './handlers/scrape.handler';
import { ClassifyHandler } from './handlers/classify.handler';
import { ExtractHandler } from './handlers/extract.handler';
import { RedisCacheService } from './services/redis-cache.service';
import { logger } from '@eventhound/shared/utils';
import { config } from './config';

async function main() {
  // Initialize services
  const broker = new MessageBroker({
    url: config.rabbitmq.url,
    exchange: config.rabbitmq.exchange,
  });

  const redisCache = new RedisCacheService(config.redis.url);

  // Initialize handlers
  const discoveryHandler = new DiscoveryHandler(broker, redisCache);
  const scrapeHandler = new ScrapeHandler(broker);
  const classifyHandler = new ClassifyHandler(broker);
  const extractHandler = new ExtractHandler(broker);

  // Connect
  await broker.connect();
  await redisCache.connect();

  // Consume messages
  await broker.consume(
    'event-processor-queue',
    [
      'discovery.events.#',
      'scrape.events.#',
      'classify.events.#',
      'extract.events.#',
    ],
    async (envelope) => {
      // Validate message
      validateMessage(envelope);

      // Route to appropriate handler
      switch (envelope.message_type) {
        case MESSAGE_TYPES.EVT_DISCOVERY_URLS_FOUND:
          await discoveryHandler.handleUrlsFound(envelope);
          break;

        case MESSAGE_TYPES.EVT_SCRAPE_PAGE_COMPLETED:
          await scrapeHandler.handleScrapeCompleted(envelope);
          break;

        case MESSAGE_TYPES.EVT_PAGE_CLASSIFIED_EVENT:
          await classifyHandler.handleClassifiedAsEvent(envelope);
          break;

        case MESSAGE_TYPES.EVT_EVENT_EXTRACTED:
          await extractHandler.handleEventExtracted(envelope);
          break;

        // ... otros casos

        default:
          logger.warn('Unhandled message type', { message_type: envelope.message_type });
      }
    }
  );

  logger.info('Event Processor started', {
    exchange: config.rabbitmq.exchange,
    queues: ['event-processor-queue'],
  });

  // Graceful shutdown
  process.on('SIGTERM', async () => {
    logger.info('SIGTERM received, shutting down gracefully');
    await broker.close();
    await redisCache.close();
    process.exit(0);
  });
}

main().catch((error) => {
  logger.error('Fatal error in Event Processor', { error });
  process.exit(1);
});
```

#### Verificación Fase 2:

```bash
# 1. Build shared package
cd packages/shared
npm run build

# 2. Build event-processor
cd ../../services/event-processor
npm run build

# 3. Test unitarios
npm test

# 4. Run service
npm run dev

# 5. Verificar logs
# Debe mostrar: "Event Processor started"

# 6. Test manual: publicar un evento de prueba
# (usar RabbitMQ Management UI o script)
```

---

## FASE 3: Discovery y Scraping Workers

### 3.1 Implementar Discovery Worker

**Objetivo:** Descubrir URLs usando 4 estrategias (sitemap, link crawl, RSS, patterns).

#### Estructura:

```
services/discovery-worker/
├── src/
│   ├── strategies/
│   │   ├── sitemap.strategy.ts      # RobotsFile, Sitemap.load()
│   │   ├── crawl.strategy.ts        # enqueueLinks con globs
│   │   ├── feed.strategy.ts         # RSS/Atom parser
│   │   ├── pattern.strategy.ts      # URL templating
│   │   ├── hybrid.strategy.ts       # Combina todas
│   │   ├── base.strategy.ts         # Interface común
│   │   └── index.ts
│   ├── handlers/
│   │   └── discover.handler.ts      # Maneja cmd.source.discover
│   ├── services/
│   │   ├── deduplication.service.ts # Redis SISMEMBER checks
│   │   └── url-filter.service.ts    # Filtros de URL
│   ├── index.ts
│   └── config.ts
├── Dockerfile
└── package.json
```

#### Estrategia Sitemap:

**services/discovery-worker/src/strategies/sitemap.strategy.ts:**
```typescript
import { Sitemap, RobotsFile } from 'crawlee';
import { DiscoverableUrl, DiscoveryStrategy, DiscoveryConfig } from './base.strategy';
import { logger } from '@eventhound/shared/utils';

export class SitemapStrategy implements DiscoveryStrategy {
  async discover(source: { base_url: string }, config: DiscoveryConfig): Promise<DiscoverableUrl[]> {
    const urls: DiscoverableUrl[] = [];

    try {
      // 1. Obtener sitemap URLs (desde config o robots.txt)
      let sitemapUrls = config.sitemap_urls || [];

      if (sitemapUrls.length === 0) {
        logger.info('Auto-discovering sitemap from robots.txt', { base_url: source.base_url });
        const robots = await RobotsFile.find(source.base_url);
        sitemapUrls = robots.getSitemapUrls();
      }

      if (sitemapUrls.length === 0) {
        logger.warn('No sitemap found', { base_url: source.base_url });
        return [];
      }

      // 2. Procesar cada sitemap
      for (const sitemapUrl of sitemapUrls) {
        logger.info('Processing sitemap', { sitemapUrl });

        const sitemap = await Sitemap.load(sitemapUrl);

        for (const entry of sitemap.urls) {
          // Aplicar filtros de content_type si están configurados
          if (this.shouldIncludeUrl(entry.loc, config)) {
            urls.push({
              url: entry.loc,
              discovered_from: { type: 'sitemap', url: sitemapUrl },
              lastmod: entry.lastmod,
              priority: entry.priority,
              changefreq: entry.changefreq,
            });
          }
        }
      }

      logger.info('Sitemap discovery completed', {
        base_url: source.base_url,
        sitemaps_processed: sitemapUrls.length,
        urls_found: urls.length,
      });

    } catch (error) {
      logger.error('Sitemap discovery failed', { error, base_url: source.base_url });
      throw error;
    }

    return urls;
  }

  private shouldIncludeUrl(url: string, config: DiscoveryConfig): boolean {
    // Aplicar content_type_filter si está configurado
    if (config.content_type_filter && config.content_type_filter.length > 0) {
      const filters = config.content_type_filter;

      // Ejemplo: solo incluir URLs que contengan /event/ si filter = ['events']
      if (filters.includes('events')) {
        return /\/(event|events|actividad|actividades|agenda)\//i.test(url);
      }
      // ... otros filtros
    }

    // Por defecto, incluir
    return true;
  }
}
```

#### Estrategia Link Crawl:

**services/discovery-worker/src/strategies/crawl.strategy.ts:**
```typescript
import { PlaywrightCrawler } from 'crawlee';
import { DiscoverableUrl, DiscoveryStrategy, DiscoveryConfig } from './base.strategy';
import { logger } from '@eventhound/shared/utils';

export class CrawlStrategy implements DiscoveryStrategy {
  async discover(source: { base_url: string }, config: DiscoveryConfig): Promise<DiscoverableUrl[]> {
    const urls: DiscoverableUrl[] = [];

    // Validar que tenemos start_urls
    if (!config.start_urls || config.start_urls.length === 0) {
      throw new Error('start_urls is required for crawl strategy');
    }

    const crawler = new PlaywrightCrawler({
      maxRequestsPerCrawl: config.max_urls || 1000,
      maxConcurrency: 5,

      async requestHandler({ page, request, enqueueLinks }) {
        // Registrar URL descubierta
        urls.push({
          url: request.url,
          discovered_from: {
            type: 'page_link',
            url: request.userData.referer,
          },
        });

        // Seguir enlaces si no hemos alcanzado max_depth
        const currentDepth = request.userData.depth || 0;

        if (currentDepth < (config.max_depth || 3)) {
          await enqueueLinks({
            strategy: 'same-hostname',
            globs: config.include_patterns || ['**/*'],
            exclude: config.exclude_patterns || [
              '**/tag/**',
              '**/category/**',
              '**/page/**',
              '**/search**',
              '**/wp-admin/**',
            ],
            transformRequestFunction: (req) => {
              req.userData.depth = currentDepth + 1;
              req.userData.referer = request.url;
              return req;
            },
          });
        }
      },

      failedRequestHandler({ request }, error) {
        logger.error('Request failed in crawl', { url: request.url, error });
      },
    });

    // Iniciar crawling desde start_urls
    await crawler.addRequests(
      config.start_urls.map((path) => ({
        url: new URL(path, source.base_url).href,
        userData: { depth: 0 },
      }))
    );

    await crawler.run();

    logger.info('Link crawl completed', {
      base_url: source.base_url,
      urls_found: urls.length,
    });

    return urls;
  }
}
```

#### Handler principal:

**services/discovery-worker/src/handlers/discover.handler.ts:**
```typescript
import { EnvelopeV1, SourceDiscoverPayload, buildDiscoveryUrlsFoundEvent, buildDiscoveryCompletedEvent } from '@urbanmoop/contracts';
import { MessageBroker } from '@eventhound/shared/messaging';
import { DeduplicationService } from '../services/deduplication.service';
import { SitemapStrategy, CrawlStrategy, FeedStrategy, PatternStrategy, HybridStrategy } from '../strategies';
import { logger } from '@eventhound/shared/utils';
import { sha256 } from '@eventhound/shared/utils';

export class DiscoverHandler {
  constructor(
    private readonly broker: MessageBroker,
    private readonly dedup: DeduplicationService
  ) {}

  async handleDiscover(envelope: EnvelopeV1<SourceDiscoverPayload>): Promise<void> {
    const { source_id, base_url, strategy, discovery_config } = envelope.payload;
    const startTime = Date.now();

    logger.info('Starting discovery', {
      source_id,
      base_url,
      strategy,
      correlation_id: envelope.correlation_id,
    });

    // Seleccionar estrategia
    const strategyImpl = this.getStrategy(strategy);

    // Ejecutar discovery
    const discoveredUrls = await strategyImpl.discover(
      { base_url },
      discovery_config || {}
    );

    logger.info('Discovery completed', {
      source_id,
      total_discovered: discoveredUrls.length,
    });

    // Deduplicación con Redis
    const { newUrls, duplicateUrls } = await this.dedup.filterDuplicates(
      source_id,
      discoveredUrls
    );

    logger.info('Deduplication complete', {
      source_id,
      new_urls: newUrls.length,
      duplicate_urls: duplicateUrls.length,
      cache_hit_rate: (duplicateUrls.length / discoveredUrls.length).toFixed(2),
    });

    // Publicar evento con URLs nuevas (batch)
    if (newUrls.length > 0) {
      const batchSize = 100;

      for (let i = 0; i < newUrls.length; i += batchSize) {
        const batch = newUrls.slice(i, i + batchSize);
        const isLastBatch = i + batchSize >= newUrls.length;

        const event = buildDiscoveryUrlsFoundEvent({
          source_id,
          tenant_id: envelope.tenant_id,
          discovery_run_id: 1, // TODO: crear en BD primero
          strategy,
          discovered_from: { type: 'sitemap' }, // TODO: depende de estrategia
          urls: batch.map(u => ({
            url: u.url,
            lastmod: u.lastmod,
            priority: u.priority,
          })),
          batch_stats: {
            total_in_batch: batch.length,
            new_urls: batch.length,
            duplicate_urls: 0,
            filtered_urls: 0,
          },
          is_final_batch: isLastBatch,
        }, {
          correlation_id: envelope.correlation_id,
          causation_id: envelope.message_id,
        });

        await this.broker.publish('discovery.events', event);
      }
    }

    // Publicar evento de completado
    const completedEvent = buildDiscoveryCompletedEvent({
      source_id,
      tenant_id: envelope.tenant_id,
      discovery_run_id: 1,
      strategy,
      stats: {
        total_urls_discovered: discoveredUrls.length,
        total_urls_queued: newUrls.length,
        total_urls_filtered: 0,
        total_urls_duplicate: duplicateUrls.length,
        cache_hit_rate: duplicateUrls.length / discoveredUrls.length,
      },
      duration_ms: Date.now() - startTime,
    }, {
      correlation_id: envelope.correlation_id,
      causation_id: envelope.message_id,
    });

    await this.broker.publish('discovery.events', completedEvent);

    logger.info('Discovery run completed successfully', { source_id });
  }

  private getStrategy(strategy: string): DiscoveryStrategy {
    switch (strategy) {
      case 'sitemap':
        return new SitemapStrategy();
      case 'link_crawl':
        return new CrawlStrategy();
      case 'rss_feed':
        return new FeedStrategy();
      case 'url_pattern':
        return new PatternStrategy();
      case 'hybrid':
        return new HybridStrategy();
      default:
        throw new Error(`Unknown strategy: ${strategy}`);
    }
  }
}
```

---

### 3.2 Implementar Scraping Worker

**Objetivo:** Obtener HTML de páginas usando Crawlee (HTTP o Browser).

#### Estructura:

```
services/scraping-worker/
├── src/
│   ├── crawlers/
│   │   ├── cheerio.crawler.ts      # HTTP scraping (rápido)
│   │   ├── playwright.crawler.ts   # Browser scraping (JS-heavy)
│   │   └── factory.ts              # Seleccionar crawler según config
│   ├── handlers/
│   │   └── scrape.handler.ts       # Maneja cmd.scrape.page.requested
│   ├── index.ts
│   └── config.ts
├── Dockerfile
└── package.json
```

**services/scraping-worker/src/crawlers/cheerio.crawler.ts:**
```typescript
import { CheerioCrawler, Configuration } from 'crawlee';
import { MessageBroker } from '@eventhound/shared/messaging';
import { buildScrapePageCompletedEvent, buildScrapePageFailedEvent } from '@urbanmoop/contracts';
import { logger } from '@eventhound/shared/utils';

// No persistir storage en disco
Configuration.set('persistStorage', false);

export class CheerioScraper {
  private crawler: CheerioCrawler;

  constructor(private readonly broker: MessageBroker) {
    this.crawler = new CheerioCrawler({
      maxRequestsPerMinute: 120,
      maxConcurrency: 10,
      requestHandler: this.handleRequest.bind(this),
      failedRequestHandler: this.handleFailedRequest.bind(this),
    });
  }

  async scrape(options: {
    url: string;
    page_id: string;
    tenant_id: string;
    correlation_id: string;
    causation_id: string;
  }): Promise<void> {
    await this.crawler.addRequests([{
      url: options.url,
      userData: {
        page_id: options.page_id,
        tenant_id: options.tenant_id,
        correlation_id: options.correlation_id,
        causation_id: options.causation_id,
        start_time: Date.now(),
      },
    }]);
  }

  async run(): Promise<void> {
    await this.crawler.run();
  }

  private async handleRequest({ request, $, response }): Promise<void> {
    const html = $.html();
    const userData = request.userData;
    const responseTimeMs = Date.now() - userData.start_time;

    logger.info('Page scraped successfully', {
      url: request.url,
      page_id: userData.page_id,
      status_code: response.statusCode,
      response_time_ms: responseTimeMs,
    });

    // Publicar evento de éxito
    const event = buildScrapePageCompletedEvent({
      page_id: userData.page_id,
      url: request.url,
      tenant_id: userData.tenant_id,
      result: {
        html,
        status_code: response.statusCode,
        headers: response.headers,
        metadata: {
          response_time_ms: responseTimeMs,
          content_length: html.length,
          crawler_type: 'cheerio',
        },
      },
    }, {
      correlation_id: userData.correlation_id,
      causation_id: userData.causation_id,
    });

    await this.broker.publish('scrape.events', event);
  }

  private async handleFailedRequest({ request, error }): Promise<void> {
    const userData = request.userData;

    logger.error('Page scraping failed', {
      url: request.url,
      page_id: userData.page_id,
      error: error.message,
      retries: request.retryCount,
    });

    // Publicar evento de error
    const event = buildScrapePageFailedEvent({
      page_id: userData.page_id,
      url: request.url,
      tenant_id: userData.tenant_id,
      error: {
        code: 'SCRAPE_FAILED',
        message: error.message,
        details: { retries: request.retryCount },
      },
    }, {
      correlation_id: userData.correlation_id,
      causation_id: userData.causation_id,
    });

    await this.broker.publish('scrape.events', event);
  }
}
```

#### Verificación Fase 3:

```bash
# 1. Build discovery-worker
cd services/discovery-worker
npm run build
npm test

# 2. Build scraping-worker
cd ../scraping-worker
npm run build
npm test

# 3. Run workers
npm run dev  # En terminales separadas

# 4. Test end-to-end: enviar comando de discovery
# (usar script o RabbitMQ Management UI)

# 5. Verificar flujo completo:
# cmd.source.discover -> evt.discovery.urls_found -> cmd.scrape.page.requested -> evt.scrape.page.completed
```

---

## FASE 4: Classification y Extraction Workers

### 4.1 Implementar Classification Worker

**Objetivo:** Determinar si una página contiene un evento usando reglas.

#### Estructura:

```
services/classification-worker/
├── src/
│   ├── classifiers/
│   │   ├── rule-based.classifier.ts    # URL patterns, CSS selectors, meta tags
│   │   ├── schema-org.classifier.ts    # Schema.org Event detection
│   │   ├── hybrid.classifier.ts        # Combina reglas + heurísticas
│   │   └── base.classifier.ts          # Interface
│   ├── handlers/
│   │   └── classify.handler.ts         # Maneja cmd.page.classify
│   ├── services/
│   │   └── rule-engine.service.ts      # Evalúa classification_rules de BD
│   ├── index.ts
│   └── config.ts
├── Dockerfile
└── package.json
```

**services/classification-worker/src/classifiers/rule-based.classifier.ts:**
```typescript
import { load } from 'cheerio';
import { ClassificationResult, Classifier } from './base.classifier';
import { logger } from '@eventhound/shared/utils';

export class RuleBasedClassifier implements Classifier {
  async classify(html: string, url: string, rules: any[]): Promise<ClassificationResult> {
    const $ = load(html);

    let score = 0;
    let matchedRules: any[] = [];
    let reason = '';

    // 1. URL Pattern rules
    for (const rule of rules.filter(r => r.rule_type === 'url_pattern')) {
      const pattern = rule.rule_config.pattern;

      if (url.includes(pattern)) {
        score += rule.score_if_match;
        matchedRules.push({
          rule_id: rule.id,
          rule_name: rule.rule_name,
          score_contribution: rule.score_if_match,
        });
      }
    }

    // 2. Schema.org Event detection
    const schemaOrgType = $('script[type="application/ld+json"]').text();
    if (schemaOrgType.includes('"@type":"Event"') || schemaOrgType.includes('"@type":"MusicEvent"')) {
      score += 1.0;
      matchedRules.push({
        rule_id: -1,
        rule_name: 'Schema.org Event detected',
        score_contribution: 1.0,
      });
    }

    // 3. Meta tags
    const ogType = $('meta[property="og:type"]').attr('content');
    if (ogType === 'event') {
      score += 0.95;
      matchedRules.push({
        rule_id: -2,
        rule_name: 'og:type=event',
        score_contribution: 0.95,
      });
    }

    // 4. Calcular score final (normalizar a 0-1)
    const finalScore = Math.min(score, 1.0);
    const isEvent = finalScore >= 0.7; // Threshold

    // 5. Generar reason
    if (isEvent) {
      reason = `Classified as event (score: ${finalScore.toFixed(2)}). Matched rules: ${matchedRules.map(r => r.rule_name).join(', ')}`;
    } else {
      reason = `Not an event (score: ${finalScore.toFixed(2)}). Below threshold.`;
    }

    // 6. Extraer datos preliminares si es evento
    const preliminaryData = isEvent ? {
      detected_title: $('h1').first().text() || $('title').text(),
      detected_date: this.extractDate($),
      detected_schema_org: schemaOrgType.includes('"@type":"Event"'),
    } : undefined;

    return {
      is_event: isEvent,
      score: finalScore,
      method: 'rule_based',
      reason,
      matched_rules: matchedRules,
      preliminary_data: preliminaryData,
    };
  }

  private extractDate($: any): string | undefined {
    // Intentar múltiples selectores comunes
    const dateSelectors = [
      '.event-date',
      '[itemprop="startDate"]',
      'time[datetime]',
      '.date',
    ];

    for (const selector of dateSelectors) {
      const dateText = $(selector).first().text().trim();
      if (dateText) return dateText;

      const dateAttr = $(selector).first().attr('datetime');
      if (dateAttr) return dateAttr;
    }

    return undefined;
  }
}
```

**services/classification-worker/src/handlers/classify.handler.ts:**
```typescript
import { EnvelopeV1, PageClassifyPayload, buildPageClassifiedEventEvent, buildPageClassifiedOtherEvent } from '@urbanmoop/contracts';
import { MessageBroker } from '@eventhound/shared/messaging';
import { RuleBasedClassifier } from '../classifiers/rule-based.classifier';
import { RuleEngineService } from '../services/rule-engine.service';
import { logger } from '@eventhound/shared/utils';

export class ClassifyHandler {
  constructor(
    private readonly broker: MessageBroker,
    private readonly ruleEngine: RuleEngineService
  ) {}

  async handleClassify(envelope: EnvelopeV1<PageClassifyPayload>): Promise<void> {
    const { page_id, url, html, source_id, classification_config } = envelope.payload;

    logger.info('Classifying page', { page_id, url, source_id });

    // 1. Obtener reglas aplicables
    const rules = await this.ruleEngine.getRulesForSource(source_id);

    // 2. Ejecutar clasificación
    const classifier = new RuleBasedClassifier();
    const result = await classifier.classify(html, url, rules);

    logger.info('Classification complete', {
      page_id,
      url,
      is_event: result.is_event,
      score: result.score,
    });

    // 3. Publicar evento apropiado
    if (result.is_event) {
      const event = buildPageClassifiedEventEvent({
        page_id,
        url,
        tenant_id: envelope.tenant_id,
        source_id,
        classification: {
          is_event: true,
          score: result.score,
          method: result.method as any,
          reason: result.reason,
          matched_rules: result.matched_rules,
          preliminary_data: result.preliminary_data,
        },
        html, // Pasar HTML para siguiente fase (extraction)
      }, {
        correlation_id: envelope.correlation_id,
        causation_id: envelope.message_id,
      });

      await this.broker.publish('classify.events', event);
    } else {
      const event = buildPageClassifiedOtherEvent({
        page_id,
        url,
        tenant_id: envelope.tenant_id,
        source_id,
        classification: {
          is_event: false,
          score: result.score,
          method: result.method as any,
          reason: result.reason,
          detected_type: 'unknown',
        },
      }, {
        correlation_id: envelope.correlation_id,
        causation_id: envelope.message_id,
      });

      await this.broker.publish('classify.events', event);
    }
  }
}
```

---

### 4.2 Implementar Extraction Worker

**Objetivo:** Extraer datos estructurados de eventos usando templates y parsing rules.

#### Estructura:

```
services/extraction-worker/
├── src/
│   ├── extractors/
│   │   ├── template-based.extractor.ts   # Usa technology_templates
│   │   ├── schema-org.extractor.ts       # Extrae de JSON-LD
│   │   ├── fallback.extractor.ts         # Heurísticas genéricas
│   │   └── base.extractor.ts
│   ├── parsers/
│   │   ├── date.parser.ts                # Parsear fechas complejas
│   │   ├── price.parser.ts               # Extraer precio
│   │   ├── location.parser.ts            # Extraer dirección
│   │   └── index.ts
│   ├── handlers/
│   │   └── extract.handler.ts            # Maneja cmd.event.extract
│   ├── services/
│   │   ├── template.service.ts           # Cargar templates de BD
│   │   └── duplicate-detection.service.ts # Detectar duplicados
│   ├── index.ts
│   └── config.ts
├── Dockerfile
└── package.json
```

**services/extraction-worker/src/extractors/schema-org.extractor.ts:**
```typescript
import { load } from 'cheerio';
import { ExtractedEventData } from '@urbanmoop/contracts';
import { logger } from '@eventhound/shared/utils';

export class SchemaOrgExtractor {
  extract(html: string, url: string): Partial<ExtractedEventData> | null {
    const $ = load(html);

    // Buscar script JSON-LD con @type Event
    const scripts = $('script[type="application/ld+json"]');

    for (const script of scripts) {
      try {
        const data = JSON.parse($(script).html() || '{}');

        if (data['@type'] === 'Event' || data['@type']?.includes('Event')) {
          logger.info('Found Schema.org Event', { url });

          return {
            title: data.name,
            description: data.description,
            starts_at: data.startDate,
            ends_at: data.endDate,
            location: data.location ? {
              name: data.location.name,
              address: data.location.address?.streetAddress,
              city: data.location.address?.addressLocality,
              region: data.location.address?.addressRegion,
              postal_code: data.location.address?.postalCode,
              country: data.location.address?.addressCountry || 'ES',
            } : undefined,
            organizer: data.organizer ? {
              name: data.organizer.name,
              url: data.organizer.url,
            } : undefined,
            price: data.offers ? {
              type: data.offers.price === '0' ? 'free' : 'paid',
              amount: parseFloat(data.offers.price),
              currency: data.offers.priceCurrency || 'EUR',
            } : undefined,
            images: data.image ? [{
              url: data.image,
              type: 'main',
            }] : undefined,
            event_url: url,
            language: 'es',
          };
        }
      } catch (error) {
        logger.warn('Failed to parse JSON-LD', { error });
      }
    }

    return null;
  }
}
```

**services/extraction-worker/src/handlers/extract.handler.ts:**
```typescript
import { EnvelopeV1, EventExtractPayload, buildEventExtractedEvent, buildEventDuplicateEvent, buildEventExtractionFailedEvent } from '@urbanmoop/contracts';
import { MessageBroker } from '@eventhound/shared/messaging';
import { SchemaOrgExtractor } from '../extractors/schema-org.extractor';
import { TemplateBasedExtractor } from '../extractors/template-based.extractor';
import { DuplicateDetectionService } from '../services/duplicate-detection.service';
import { logger } from '@eventhound/shared/utils';

export class ExtractHandler {
  constructor(
    private readonly broker: MessageBroker,
    private readonly duplicateDetection: DuplicateDetectionService
  ) {}

  async handleExtract(envelope: EnvelopeV1<EventExtractPayload>): Promise<void> {
    const { page_id, url, html, source_id, extraction_config, classification_hints } = envelope.payload;

    logger.info('Extracting event data', { page_id, url, source_id });

    try {
      // 1. Intentar Schema.org primero (más confiable)
      let extractedData = null;
      let method = 'unknown';

      if (classification_hints?.detected_schema_org) {
        const schemaExtractor = new SchemaOrgExtractor();
        extractedData = schemaExtractor.extract(html, url);

        if (extractedData) {
          method = 'schema_org';
          logger.info('Extracted using Schema.org', { page_id });
        }
      }

      // 2. Fallback a template-based
      if (!extractedData) {
        const templateExtractor = new TemplateBasedExtractor();
        extractedData = await templateExtractor.extract(html, url, source_id, extraction_config);
        method = 'template_based';
      }

      // 3. Validar campos obligatorios
      if (!extractedData || !extractedData.title || !extractedData.starts_at) {
        throw new Error('Missing required fields: title or starts_at');
      }

      // 4. Detectar duplicados
      const duplicate = await this.duplicateDetection.findDuplicate(
        extractedData.event_url,
        extractedData.title,
        extractedData.starts_at,
        source_id
      );

      if (duplicate) {
        logger.info('Duplicate event detected', { page_id, original_event_id: duplicate.id });

        const duplicateEvent = buildEventDuplicateEvent({
          page_id,
          url,
          tenant_id: envelope.tenant_id,
          source_id,
          duplicate_info: {
            original_event_id: duplicate.id,
            reason: 'same_url',
            similarity_score: 1.0,
          },
        }, {
          correlation_id: envelope.correlation_id,
          causation_id: envelope.message_id,
        });

        await this.broker.publish('extract.events', duplicateEvent);
        return;
      }

      // 5. Publicar evento de éxito
      const event = buildEventExtractedEvent({
        page_id,
        url,
        tenant_id: envelope.tenant_id,
        source_id,
        extracted_event: extractedData as any,
        extraction_metadata: {
          method,
          confidence: 0.9,
          template_id: extraction_config?.technology_template_id,
        },
      }, {
        correlation_id: envelope.correlation_id,
        causation_id: envelope.message_id,
      });

      await this.broker.publish('extract.events', event);

      logger.info('Event extracted successfully', { page_id, method });

    } catch (error: any) {
      logger.error('Event extraction failed', { page_id, error: error.message });

      // Publicar evento de error
      const failedEvent = buildEventExtractionFailedEvent({
        page_id,
        url,
        tenant_id: envelope.tenant_id,
        source_id,
        error: {
          code: 'PARSING_ERROR',
          message: error.message,
        },
      }, {
        correlation_id: envelope.correlation_id,
        causation_id: envelope.message_id,
      });

      await this.broker.publish('extract.events', failedEvent);
    }
  }
}
```

#### Verificación Fase 4:

```bash
# 1. Build classification-worker
cd services/classification-worker
npm run build
npm test

# 2. Build extraction-worker
cd ../extraction-worker
npm run build
npm test

# 3. Run workers
npm run dev

# 4. Test end-to-end completo:
# cmd.source.discover -> ... -> evt.event.extracted

# 5. Verificar en BD:
psql $DATABASE_URL -c "SELECT COUNT(*) FROM webscraping.events WHERE correlation_id IS NOT NULL;"
# Debe mostrar eventos extraídos
```

---

## FASE 5: API Gateway, Testing y Producción

### 5.1 Implementar API Gateway

**Objetivo:** REST API para usuarios y administradores.

#### Estructura:

```
services/api-gateway/
├── src/
│   ├── routes/
│   │   ├── sources.routes.ts           # CRUD de sources
│   │   ├── discovery.routes.ts         # POST /sources/:id/discover
│   │   ├── events.routes.ts            # GET /events, GET /events/:id
│   │   ├── pages.routes.ts             # GET /pages (admin)
│   │   └── index.ts
│   ├── controllers/
│   │   ├── sources.controller.ts
│   │   ├── discovery.controller.ts
│   │   ├── events.controller.ts
│   │   └── index.ts
│   ├── middleware/
│   │   ├── auth.middleware.ts          # Autenticación (opcional)
│   │   ├── validation.middleware.ts    # Validación con Zod
│   │   ├── error.middleware.ts         # Error handling
│   │   └── index.ts
│   ├── services/
│   │   ├── source.service.ts
│   │   ├── event.service.ts
│   │   └── index.ts
│   ├── index.ts
│   └── config.ts
├── Dockerfile
└── package.json
```

**services/api-gateway/src/routes/discovery.routes.ts:**
```typescript
import { Router } from 'express';
import { DiscoveryController } from '../controllers/discovery.controller';
import { validateRequest } from '../middleware/validation.middleware';
import { z } from 'zod';

const router = Router();
const controller = new DiscoveryController();

const startDiscoverySchema = z.object({
  body: z.object({
    strategy: z.enum(['sitemap', 'link_crawl', 'rss_feed', 'url_pattern', 'hybrid']).default('hybrid'),
    discovery_config: z.object({
      max_urls: z.number().int().positive().optional(),
      max_depth: z.number().int().positive().optional(),
    }).optional(),
  }),
});

router.post(
  '/sources/:id/discover',
  validateRequest(startDiscoverySchema),
  controller.startDiscovery
);

router.get(
  '/sources/:id/discovery-runs',
  controller.getDiscoveryRuns
);

router.get(
  '/sources/:id/discovery-stats',
  controller.getDiscoveryStats
);

export default router;
```

**services/api-gateway/src/controllers/discovery.controller.ts:**
```typescript
import { Request, Response } from 'express';
import { MessageBroker } from '@eventhound/shared/messaging';
import { buildSourceDiscoverCommand } from '@urbanmoop/contracts';
import { db, sources } from '@eventhound/shared/database';
import { eq } from 'drizzle-orm';
import { logger } from '@eventhound/shared/utils';
import { v4 as uuidv4 } from 'uuid';

export class DiscoveryController {
  private broker: MessageBroker;

  constructor() {
    this.broker = new MessageBroker({
      url: process.env.RABBITMQ_URL!,
      exchange: process.env.RABBITMQ_EXCHANGE!,
    });

    this.broker.connect();
  }

  startDiscovery = async (req: Request, res: Response) => {
    const sourceId = parseInt(req.params.id);
    const { strategy, discovery_config } = req.body;

    try {
      // 1. Verificar que source existe
      const [source] = await db
        .select()
        .from(sources)
        .where(eq(sources.id, sourceId))
        .limit(1);

      if (!source) {
        return res.status(404).json({ error: 'Source not found' });
      }

      // 2. Crear comando de discovery
      const command = buildSourceDiscoverCommand({
        source_id: sourceId,
        base_url: source.base_url,
        tenant_id: 'default', // TODO: extraer de auth
        strategy,
        discovery_config,
      });

      // 3. Publicar comando
      await this.broker.publish('discovery.commands', command);

      logger.info('Discovery started', {
        source_id: sourceId,
        strategy,
        correlation_id: command.correlation_id,
      });

      // 4. Responder
      res.status(202).json({
        message: 'Discovery started',
        correlation_id: command.correlation_id,
        source_id: sourceId,
        strategy,
      });

    } catch (error: any) {
      logger.error('Failed to start discovery', { error, source_id: sourceId });
      res.status(500).json({ error: 'Internal server error' });
    }
  };

  getDiscoveryRuns = async (req: Request, res: Response) => {
    // TODO: implementar query a discovery_runs table
    res.json({ runs: [] });
  };

  getDiscoveryStats = async (req: Request, res: Response) => {
    // TODO: implementar query a discovery_stats view
    res.json({ stats: {} });
  };
}
```

**services/api-gateway/src/index.ts:**
```typescript
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import morgan from 'morgan';
import sourcesRoutes from './routes/sources.routes';
import discoveryRoutes from './routes/discovery.routes';
import eventsRoutes from './routes/events.routes';
import pagesRoutes from './routes/pages.routes';
import { errorMiddleware } from './middleware/error.middleware';
import { logger } from '@eventhound/shared/utils';
import { config } from './config';

const app = express();

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('combined'));

// Routes
app.use('/api', sourcesRoutes);
app.use('/api', discoveryRoutes);
app.use('/api', eventsRoutes);
app.use('/api', pagesRoutes);

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Error handling
app.use(errorMiddleware);

// Start server
const PORT = config.port || 3000;

app.listen(PORT, () => {
  logger.info(`API Gateway listening on port ${PORT}`);
});
```

---

### 5.2 Testing Completo

**Objetivo:** Tests unitarios + integración + E2E con alta cobertura.

#### Estrategia:

**Tests Unitarios:**
- Cada servicio con tests de lógica de negocio
- Mocks de dependencias externas (DB, RabbitMQ, Redis)
- Herramientas: Jest, ts-jest
- Cobertura mínima: 80%

**Tests de Integración:**
- Verificar integración entre servicios
- Usar Testcontainers para PostgreSQL, RabbitMQ, Redis reales
- Tests de flujos completos end-to-end

**Tests E2E:**
- API Gateway → Workers → BD
- Escenarios reales de descubrimiento, scraping, extracción

#### Archivos a crear:

**tests/integration/discovery-flow.test.ts:**
```typescript
import { MessageBroker } from '@eventhound/shared/messaging';
import { buildSourceDiscoverCommand } from '@urbanmoop/contracts';
import { db, pages } from '@eventhound/shared/database';
import { PostgreSqlContainer } from '@testcontainers/postgresql';
import { GenericContainer } from 'testcontainers';
import { eq } from 'drizzle-orm';

describe('Discovery Flow E2E', () => {
  let postgresContainer: PostgreSqlContainer;
  let rabbitmqContainer: GenericContainer;
  let broker: MessageBroker;

  beforeAll(async () => {
    // Start containers
    postgresContainer = await new PostgreSqlContainer().start();
    rabbitmqContainer = await new GenericContainer('rabbitmq:3.12-alpine')
      .withExposedPorts(5672)
      .start();

    // Initialize services
    // ... setup DB, broker, etc.
  });

  afterAll(async () => {
    await postgresContainer.stop();
    await rabbitmqContainer.stop();
  });

  it('should discover URLs and persist them', async () => {
    // 1. Enviar comando de discovery
    const command = buildSourceDiscoverCommand({
      source_id: 1,
      base_url: 'https://example.com',
      tenant_id: 'test',
      strategy: 'sitemap',
    });

    await broker.publish('discovery.commands', command);

    // 2. Esperar a que se procese (polling o timeout)
    await new Promise(resolve => setTimeout(resolve, 5000));

    // 3. Verificar que se crearon páginas en BD
    const pagesCount = await db
      .select({ count: pages.id })
      .from(pages)
      .where(eq(pages.source_id, 1));

    expect(pagesCount).toBeGreaterThan(0);
  });

  // ... más tests
});
```

**package.json scripts:**
```json
{
  "scripts": {
    "test": "jest --coverage",
    "test:unit": "jest --testPathPattern=unit",
    "test:integration": "jest --testPathPattern=integration",
    "test:e2e": "jest --testPathPattern=e2e",
    "test:watch": "jest --watch"
  }
}
```

---

### 5.3 CI/CD con GitHub Actions

**Objetivo:** Pipeline automatizado de testing, build y deploy.

#### Archivos a crear:

**.github/workflows/ci.yml:**
```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Lint
        run: npm run lint

      - name: Format check
        run: npm run format:check

  typecheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '20'
          cache: 'npm'

      - run: npm ci
      - run: npm run typecheck

  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_DB: eventhound_test
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

      rabbitmq:
        image: rabbitmq:3.12-alpine
        ports:
          - 5672:5672

      redis:
        image: redis:7-alpine
        ports:
          - 6379:6379

    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '20'
          cache: 'npm'

      - run: npm ci

      - name: Run unit tests
        run: npm run test:unit

      - name: Run integration tests
        run: npm run test:integration
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/eventhound_test
          RABBITMQ_URL: amqp://localhost:5672
          REDIS_URL: redis://localhost:6379

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage/lcov.info
          flags: unittests
          name: eventhound-coverage

  build:
    runs-on: ubuntu-latest
    needs: [lint, typecheck, test]
    strategy:
      matrix:
        service:
          - api-gateway
          - discovery-worker
          - scraping-worker
          - classification-worker
          - extraction-worker
          - event-processor
    steps:
      - uses: actions/checkout@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2

      - name: Build Docker image
        uses: docker/build-push-action@v4
        with:
          context: ./services/${{ matrix.service }}
          push: false
          tags: eventhound/${{ matrix.service }}:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

**.github/workflows/deploy.yml:**
```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Deploy to production
        run: |
          # TODO: kubectl apply, helm upgrade, etc.
          echo "Deploying to production"
```

---

### 5.4 Docker y Kubernetes

**Objetivo:** Despliegue containerizado en producción.

#### Archivos a crear:

**services/discovery-worker/Dockerfile:**
```dockerfile
FROM node:20-alpine AS builder

WORKDIR /app

# Install dependencies
COPY package*.json ./
COPY packages/shared/package*.json ./packages/shared/
RUN npm ci --workspace=packages/shared

COPY services/discovery-worker/package*.json ./services/discovery-worker/
RUN npm ci --workspace=services/discovery-worker

# Build
COPY packages/shared ./packages/shared
COPY services/discovery-worker ./services/discovery-worker
RUN npm run build --workspace=packages/shared
RUN npm run build --workspace=services/discovery-worker

# Production image
FROM node:20-alpine

WORKDIR /app

# Install production dependencies only
COPY package*.json ./
COPY packages/shared/package*.json ./packages/shared/
COPY services/discovery-worker/package*.json ./services/discovery-worker/
RUN npm ci --workspace=packages/shared --omit=dev
RUN npm ci --workspace=services/discovery-worker --omit=dev

# Copy built artifacts
COPY --from=builder /app/packages/shared/dist ./packages/shared/dist
COPY --from=builder /app/services/discovery-worker/dist ./services/discovery-worker/dist

USER node

CMD ["node", "services/discovery-worker/dist/index.js"]
```

**docker/docker-compose.prod.yml:**
```yaml
version: '3.8'

services:
  api-gateway:
    build:
      context: ..
      dockerfile: services/api-gateway/Dockerfile
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: ${DATABASE_URL}
      RABBITMQ_URL: ${RABBITMQ_URL}
      REDIS_URL: ${REDIS_URL}
    depends_on:
      - postgres
      - rabbitmq
      - redis

  discovery-worker:
    build:
      context: ..
      dockerfile: services/discovery-worker/Dockerfile
    environment:
      RABBITMQ_URL: ${RABBITMQ_URL}
      REDIS_URL: ${REDIS_URL}
    depends_on:
      - rabbitmq
      - redis
    deploy:
      replicas: 2

  scraping-worker:
    build:
      context: ..
      dockerfile: services/scraping-worker/Dockerfile
    environment:
      RABBITMQ_URL: ${RABBITMQ_URL}
    depends_on:
      - rabbitmq
    deploy:
      replicas: 3

  classification-worker:
    build:
      context: ..
      dockerfile: services/classification-worker/Dockerfile
    environment:
      RABBITMQ_URL: ${RABBITMQ_URL}
    depends_on:
      - rabbitmq
    deploy:
      replicas: 2

  extraction-worker:
    build:
      context: ..
      dockerfile: services/extraction-worker/Dockerfile
    environment:
      RABBITMQ_URL: ${RABBITMQ_URL}
    depends_on:
      - rabbitmq
    deploy:
      replicas: 2

  event-processor:
    build:
      context: ..
      dockerfile: services/event-processor/Dockerfile
    environment:
      DATABASE_URL: ${DATABASE_URL}
      RABBITMQ_URL: ${RABBITMQ_URL}
      REDIS_URL: ${REDIS_URL}
    depends_on:
      - postgres
      - rabbitmq
      - redis
    deploy:
      replicas: 1  # Single writer!

  # Infraestructura (usar versiones de producción)
  postgres:
    image: postgres:15
    # ... config de producción

  rabbitmq:
    image: rabbitmq:3.12-management
    # ... config de producción

  redis:
    image: redis:7
    # ... config de producción
```

**k8s/deployment.yaml** (ejemplo):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: discovery-worker
spec:
  replicas: 2
  selector:
    matchLabels:
      app: discovery-worker
  template:
    metadata:
      labels:
        app: discovery-worker
    spec:
      containers:
      - name: discovery-worker
        image: eventhound/discovery-worker:latest
        env:
        - name: RABBITMQ_URL
          valueFrom:
            secretKeyRef:
              name: eventhound-secrets
              key: rabbitmq-url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: eventhound-secrets
              key: redis-url
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
```

---

## Verificación End-to-End

### Flujo Completo a Verificar

```bash
# 1. Levantar toda la infraestructura
docker-compose -f docker/docker-compose.prod.yml up -d

# 2. Verificar que todos los servicios están healthy
docker ps --filter "status=running"

# 3. Crear un source en BD
psql $DATABASE_URL << EOF
INSERT INTO webscraping.sources (name, base_url, status)
VALUES ('Test Source', 'https://example.com', 'active');
EOF

# 4. Iniciar discovery via API
curl -X POST http://localhost:3000/api/sources/1/discover \
  -H "Content-Type: application/json" \
  -d '{
    "strategy": "sitemap",
    "discovery_config": {
      "max_urls": 100
    }
  }'

# 5. Monitorear logs en tiempo real
docker-compose logs -f discovery-worker scraping-worker classification-worker extraction-worker event-processor

# 6. Esperar procesamiento completo (polling)
while true; do
  COUNT=$(psql $DATABASE_URL -tAc "SELECT COUNT(*) FROM webscraping.events WHERE source_id = 1;")
  echo "Events extracted: $COUNT"
  if [ "$COUNT" -gt 0 ]; then
    echo "Success! Events extracted."
    break
  fi
  sleep 5
done

# 7. Verificar datos en BD
psql $DATABASE_URL << EOF
-- Ver estadísticas de discovery
SELECT * FROM webscraping.discovery_stats WHERE source_id = 1;

-- Ver páginas procesadas
SELECT status, COUNT(*) FROM webscraping.pages WHERE source_id = 1 GROUP BY status;

-- Ver eventos extraídos
SELECT id, title, starts_at, venue_id FROM webscraping.events WHERE source_id = 1 LIMIT 10;

-- Ver historial de procesamiento
SELECT message_type, to_status, occurred_at
FROM webscraping.page_processing_history
WHERE page_id IN (SELECT id FROM webscraping.pages WHERE source_id = 1)
ORDER BY occurred_at DESC
LIMIT 20;
EOF

# 8. Consultar eventos via API
curl http://localhost:3000/api/events?source_id=1 | jq

# 9. Verificar métricas (Prometheus/Grafana si están configurados)
# ...

# 10. Verificar RabbitMQ Management UI
open http://localhost:15672
# Login: eventhound/eventhound_dev
# Verificar queues, exchanges, mensajes procesados
```

---

## Archivos Críticos a Crear/Modificar

### Resumen de Entregables

| Fase | Archivos a Crear | Cantidad Estimada |
|------|------------------|-------------------|
| **Fase 1** | Contratos (urbanmoop-contracts), Migraciones SQL, Docker Compose | ~25 archivos |
| **Fase 2** | Shared package, Event Processor | ~20 archivos |
| **Fase 3** | Discovery Worker, Scraping Worker | ~25 archivos |
| **Fase 4** | Classification Worker, Extraction Worker | ~25 archivos |
| **Fase 5** | API Gateway, Tests, CI/CD, Kubernetes | ~40 archivos |
| **Total** | | **~135 archivos TypeScript/SQL/YAML** |

### Prioridad de Implementación

**Crítico (bloquea todo):**
1. Contratos en urbanmoop-contracts (13 nuevos)
2. Migraciones SQL 006, 007, 008
3. Paquete shared (database, messaging, utils)
4. Event Processor (single writer)

**Alta (flujo core):**
5. Discovery Worker (todas las estrategias)
6. Scraping Worker (Cheerio + Playwright)
7. Classification Worker (rule-based)
8. Extraction Worker (template-based + Schema.org)

**Media (operacional):**
9. API Gateway (REST endpoints)
10. Tests (unit + integration)
11. Docker Compose production

**Baja (nice-to-have):**
12. Kubernetes manifests
13. CI/CD avanzado
14. Monitoring (Prometheus/Grafana)

---

## Consideraciones Técnicas

### Escalabilidad

- **Discovery Worker**: Puede escalar horizontalmente (N instancias) pero coordinar con locks para evitar descubrir el mismo source 2 veces simultáneamente
- **Scraping Worker**: Escala fácilmente (stateless), limitar concurrency por sitio para respetar rate limits
- **Classification/Extraction Workers**: Stateless, escalar según carga de CPU
- **Event Processor**: **SOLO UNA INSTANCIA** (single writer), no escalar horizontalmente

### Rate Limiting

- Implementar rate limiting por source en Scraping Worker
- Respetar robots.txt y crawl-delay
- Usar Redis para shared rate limiting entre instancias

### Monitoring y Observabilidad

- Logs estructurados con Winston (formato JSON)
- Métricas con Prometheus (contadores de mensajes procesados, errores, latencias)
- Trazabilidad completa con correlation_id en todos los logs
- Dashboards Grafana para visibilidad operacional

### Seguridad

- No exponer credenciales en código (usar secrets management)
- Autenticación JWT en API Gateway (opcional para MVP)
- Validación estricta de inputs con Zod
- Rate limiting en API Gateway (express-rate-limit)

### Performance

- **PostgreSQL**: Índices en `url_hash`, `status`, `correlation_id`, `source_id`
- **Redis**: TTL adecuados para cachés, pipelines para operaciones batch
- **RabbitMQ**: Prefetch count configurado, durable queues
- **Crawlee**: Storage en memoria (no disco), request queue optimizado

---

## Timeline Estimado

| Fase | Duración | Dependencias | Hitos |
|------|----------|--------------|-------|
| Fase 1 | 2-3 semanas | Ninguna | Contratos publicados, BD migrada, infraestructura levantada |
| Fase 2 | 2 semanas | Fase 1 | Event Processor funcionando, mensajes persistidos |
| Fase 3 | 3 semanas | Fase 2 | Discovery + Scraping funcionando, URLs en BD |
| Fase 4 | 2 semanas | Fase 3 | Classification + Extraction, eventos en BD |
| Fase 5 | 2-3 semanas | Fase 4 | API pública, tests completos, CI/CD, deploy |

**Total: 11-13 semanas (~3 meses)**

---

## Próximos Pasos Inmediatos

1. **Crear estructura de monorepo**:
   ```bash
   mkdir -p packages/shared services/{api-gateway,discovery-worker,scraping-worker,classification-worker,extraction-worker,event-processor}
   npm init -y
   # ... configurar workspaces
   ```

2. **Implementar primeros 3 contratos en urbanmoop-contracts**:
   - `cmd.page.classify`
   - `evt.page.classified.event`
   - `evt.page.classified.other`

3. **Ejecutar migraciones 006-008**:
   ```bash
   psql $DATABASE_URL -f migrations/006_add_processing_tracking.sql
   psql $DATABASE_URL -f migrations/007_add_classification_fields.sql
   psql $DATABASE_URL -f migrations/008_add_discovery_tracking.sql
   ```

4. **Crear Docker Compose dev**:
   ```bash
   docker-compose -f docker/docker-compose.dev.yml up -d
   ```

5. **Implementar paquete shared**:
   - Drizzle ORM schemas
   - RabbitMQ MessageBroker
   - Redis client
   - Logger (Winston)

---

## Referencias

- [ARCHITECTURE.md](../../../Users/cruiz/DevProjects/UrbanMoop/eventhound/docs/ARCHITECTURE.md) - Arquitectura completa
- [MIGRATIONS.md](../../../Users/cruiz/DevProjects/UrbanMoop/eventhound/docs/MIGRATIONS.md) - Schemas de BD
- [CONTRACTS.md](../../../Users/cruiz/DevProjects/UrbanMoop/eventhound/docs/CONTRACTS.md) - Contratos de mensajería
- [Crawlee Documentation](https://crawlee.dev/) - Motor de scraping
- [Drizzle ORM](https://orm.drizzle.team/) - ORM TypeScript
- [RabbitMQ Tutorials](https://www.rabbitmq.com/getstarted.html) - Message broker
