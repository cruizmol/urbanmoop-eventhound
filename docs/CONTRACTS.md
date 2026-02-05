# Eventhound - Especificación de Contratos

## Índice

1. [Visión General](#visión-general)
2. [Envelope Estándar](#envelope-estándar)
3. [Catálogo de Mensajes](#catálogo-de-mensajes)
4. [Contratos Existentes](#contratos-existentes)
5. [Nuevos Contratos Requeridos](#nuevos-contratos-requeridos)
6. [Schemas Zod Completos](#schemas-zod-completos)
7. [Builders Recomendados](#builders-recomendados)
8. [Flujo de Mensajes](#flujo-de-mensajes)
9. [Guía de Implementación](#guía-de-implementación)

---

## Visión General

Este documento especifica los contratos de mensajería necesarios para el proyecto Eventhound. Estos contratos deben implementarse en el paquete `@urbanmoop/contracts`.

### Principios

| Principio | Descripción |
|-----------|-------------|
| **Agnósticos de implementación** | Los contratos NO exponen detalles internos (ej: Crawlee) |
| **Versionados** | Cada schema tiene `schema_version` para evolución controlada |
| **Validados en runtime** | Zod valida estructura y tipos en tiempo de ejecución |
| **Trazables** | `correlation_id` y `causation_id` permiten seguir el flujo completo |

### Convenciones de Naming

```
Commands: cmd.<aggregate>.<action>
Events:   evt.<aggregate>.<past_participle>
```

**Ejemplos:**
- `cmd.page.process_request` - Solicitar procesamiento
- `evt.page.classified.event` - Página clasificada como evento
- `evt.event.created` - Evento creado en BD

---

## Envelope Estándar

Todos los mensajes deben cumplir el envelope v1:

```typescript
interface EnvelopeV1<T = unknown> {
  // Identificación
  message_id: string;        // UUID único del mensaje
  message_type: string;      // Tipo de mensaje (cmd.* o evt.*)
  schema_version: number;    // Versión del schema (empezando en 1)

  // Timestamps
  occurred_at: string;       // ISO 8601 timestamp

  // Trazabilidad
  correlation_id: string;    // UUID para correlacionar todo el flujo
  causation_id?: string;     // UUID del mensaje que causó este

  // Contexto
  tenant_id: string;         // Identificador del tenant

  // Actor (opcional)
  actor?: {
    user_id?: number;
    role?: string;
  };

  // Aggregate
  aggregate: {
    type: string;            // Tipo de entidad (page, event, source)
    id: string;              // ID de la entidad
  };

  // Payload específico del mensaje
  payload: T;
}
```

---

## Catálogo de Mensajes

### Resumen Completo

| Dominio | Message Type | Versión | Estado | Descripción |
|---------|--------------|---------|--------|-------------|
| **Page** | `cmd.page.process_request` | v1 | ✅ Existe | Solicitar procesamiento de página |
| **Page** | `evt.page.processing_started` | v1 | ✅ Existe | Procesamiento iniciado |
| **Page** | `evt.page.processed` | v1 | ✅ Existe | Procesamiento completado |
| **Page** | `evt.page.failed` | v1 | ✅ Existe | Procesamiento fallido |
| **Scrape** | `cmd.scrape.page.requested` | v1 | ✅ Existe | Solicitar scraping |
| **Scrape** | `evt.scrape.page.completed` | v1 | ✅ Existe | Scraping completado |
| **Scrape** | `evt.scrape.page.failed` | v1 | ✅ Existe | Scraping fallido |
| **Classify** | `cmd.page.classify` | v1 | 🆕 Nuevo | Solicitar clasificación |
| **Classify** | `evt.page.classified.event` | v1 | 🆕 Nuevo | Clasificado como evento |
| **Classify** | `evt.page.classified.other` | v1 | 🆕 Nuevo | Clasificado como no-evento |
| **Extract** | `cmd.event.extract` | v1 | 🆕 Nuevo | Solicitar extracción de datos |
| **Extract** | `evt.event.extracted` | v1 | 🆕 Nuevo | Datos extraídos exitosamente |
| **Extract** | `evt.event.duplicate` | v1 | 🆕 Nuevo | Evento duplicado detectado |
| **Extract** | `evt.event.extraction_failed` | v1 | 🆕 Nuevo | Extracción fallida |
| **Event** | `evt.event.created` | v1 | 🆕 Nuevo | Evento persistido en BD |
| **Event** | `evt.event.updated` | v1 | 🆕 Nuevo | Evento actualizado en BD |
| **Discovery** | `cmd.source.discover` | v1 | 🆕 Nuevo | Iniciar descubrimiento de URLs |
| **Discovery** | `evt.discovery.urls_found` | v1 | 🆕 Nuevo | URLs descubiertas |
| **Discovery** | `evt.discovery.completed` | v1 | 🆕 Nuevo | Descubrimiento completado |
| **Discovery** | `evt.discovery.failed` | v1 | 🆕 Nuevo | Descubrimiento fallido |

---

## Contratos Existentes

Los siguientes contratos ya existen en `@urbanmoop/contracts`:

### cmd.page.process_request

```typescript
const PageProcessRequestPayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  options: z.object({
    priority: z.enum(['low', 'normal', 'high']).optional(),
    timeout_ms: z.number().int().positive().optional(),
  }).optional(),
});
```

### evt.page.processing_started

```typescript
const PageProcessingStartedPayloadSchema = z.object({
  page_id: z.string().uuid(),
  tenant_id: z.string(),
  started_at: z.string().datetime().optional(),
});
```

### cmd.scrape.page.requested

```typescript
const ScrapePageRequestedPayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  scrape_config: z.object({
    user_agent: z.string().optional(),
    timeout_ms: z.number().int().positive().optional(),
    retry_count: z.number().int().nonnegative().optional(),
    requires_javascript: z.boolean().optional(),
  }).optional(),
});
```

### evt.scrape.page.completed

```typescript
const ScrapePageCompletedPayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  result: z.object({
    html: z.string(),
    status_code: z.number().int(),
    headers: z.record(z.string()).optional(),
    metadata: z.object({
      response_time_ms: z.number().int().optional(),
      content_length: z.number().int().optional(),
      content_type: z.string().optional(),
    }).optional(),
  }),
  scraped_at: z.string().datetime().optional(),
});
```

### evt.scrape.page.failed

```typescript
const ScrapePageFailedPayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  error: z.object({
    code: z.string(),
    message: z.string(),
    status_code: z.number().int().optional(),
    details: z.record(z.unknown()).optional(),
  }),
  failed_at: z.string().datetime().optional(),
});
```

---

## Nuevos Contratos Requeridos

### Dominio: Classification

#### cmd.page.classify

**Propósito:** Solicitar clasificación de una página para determinar si contiene un evento.

```typescript
// MESSAGE_TYPES.CMD_PAGE_CLASSIFY = 'cmd.page.classify'

const PageClassifyPayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  source_id: z.number().int().positive(),

  // HTML a clasificar (del scraping)
  html: z.string(),
  content_hash: z.string().optional(),

  // Configuración de clasificación
  classification_config: z.object({
    // Método preferido
    method: z.enum(['rule_based', 'ml_model', 'hybrid']).default('rule_based'),

    // Umbral mínimo de confianza
    min_confidence: z.number().min(0).max(1).default(0.7),

    // Reglas específicas a aplicar (IDs)
    rule_ids: z.array(z.number().int()).optional(),

    // Forzar resultado (para testing/override manual)
    force_result: z.boolean().optional(),
  }).optional(),
});

type PageClassifyPayload = z.infer<typeof PageClassifyPayloadSchema>;
```

#### evt.page.classified.event

**Propósito:** Indica que una página fue clasificada como evento.

```typescript
// MESSAGE_TYPES.EVT_PAGE_CLASSIFIED_EVENT = 'evt.page.classified.event'

const PageClassifiedEventPayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  source_id: z.number().int().positive(),

  // Resultado de clasificación
  classification: z.object({
    is_event: z.literal(true),
    score: z.number().min(0).max(1),
    method: z.enum(['rule_based', 'ml_model', 'hybrid', 'manual']),
    reason: z.string().optional(),

    // Reglas que matchearon (si rule_based)
    matched_rules: z.array(z.object({
      rule_id: z.number().int(),
      rule_name: z.string(),
      score_contribution: z.number(),
    })).optional(),

    // Datos preliminares detectados
    preliminary_data: z.object({
      detected_title: z.string().optional(),
      detected_date: z.string().optional(),
      detected_schema_org: z.boolean().optional(),
    }).optional(),
  }),

  // HTML para siguiente fase (extracción)
  html: z.string(),
  content_hash: z.string().optional(),

  classified_at: z.string().datetime().optional(),
});

type PageClassifiedEventPayload = z.infer<typeof PageClassifiedEventPayloadSchema>;
```

#### evt.page.classified.other

**Propósito:** Indica que una página NO contiene un evento.

```typescript
// MESSAGE_TYPES.EVT_PAGE_CLASSIFIED_OTHER = 'evt.page.classified.other'

const PageClassifiedOtherPayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  source_id: z.number().int().positive(),

  // Resultado de clasificación
  classification: z.object({
    is_event: z.literal(false),
    score: z.number().min(0).max(1),
    method: z.enum(['rule_based', 'ml_model', 'hybrid', 'manual']),
    reason: z.string().optional(),

    // Tipo detectado (si se pudo determinar)
    detected_type: z.enum([
      'listing',      // Página de listado
      'category',     // Página de categoría
      'search',       // Página de búsqueda
      'article',      // Artículo/blog post
      'static',       // Página estática
      'unknown'       // No determinado
    ]).optional(),
  }),

  classified_at: z.string().datetime().optional(),
});

type PageClassifiedOtherPayload = z.infer<typeof PageClassifiedOtherPayloadSchema>;
```

---

### Dominio: Extraction

#### cmd.event.extract

**Propósito:** Solicitar extracción de datos de evento de una página clasificada.

```typescript
// MESSAGE_TYPES.CMD_EVENT_EXTRACT = 'cmd.event.extract'

const EventExtractPayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  source_id: z.number().int().positive(),

  // HTML a procesar
  html: z.string(),
  content_hash: z.string().optional(),

  // Configuración de extracción
  extraction_config: z.object({
    // ID del template tecnológico a usar
    technology_template_id: z.number().int().optional(),

    // Overrides de selectores
    selector_overrides: z.record(z.string()).optional(),

    // Idioma esperado del contenido
    expected_language: z.string().length(2).default('es'),

    // Forzar re-extracción aunque ya exista
    force_extraction: z.boolean().default(false),
  }).optional(),

  // Datos preliminares de clasificación (hints)
  classification_hints: z.object({
    detected_title: z.string().optional(),
    detected_date: z.string().optional(),
    detected_schema_org: z.boolean().optional(),
  }).optional(),
});

type EventExtractPayload = z.infer<typeof EventExtractPayloadSchema>;
```

#### evt.event.extracted

**Propósito:** Indica que los datos de evento fueron extraídos exitosamente.

```typescript
// MESSAGE_TYPES.EVT_EVENT_EXTRACTED = 'evt.event.extracted'

const EventExtractedPayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  source_id: z.number().int().positive(),

  // Datos extraídos del evento
  extracted_event: z.object({
    // Campos obligatorios
    title: z.string().min(1),
    starts_at: z.string().datetime(),

    // Campos opcionales
    description: z.string().optional(),
    ends_at: z.string().datetime().optional(),

    // Ubicación
    location: z.object({
      name: z.string().optional(),
      address: z.string().optional(),
      city: z.string().optional(),
      region: z.string().optional(),
      country: z.string().default('ES'),
      postal_code: z.string().optional(),
      latitude: z.number().optional(),
      longitude: z.number().optional(),
    }).optional(),

    // Organizador
    organizer: z.object({
      name: z.string(),
      url: z.string().url().optional(),
    }).optional(),

    // Precio
    price: z.object({
      type: z.enum(['free', 'paid', 'donation', 'variable']),
      amount: z.number().nonnegative().optional(),
      currency: z.string().length(3).default('EUR'),
      text: z.string().optional(),
    }).optional(),

    // Categorías
    categories: z.array(z.string()).optional(),

    // Grupos de edad
    age_group: z.object({
      name: z.string().optional(),
      min_age: z.number().int().nonnegative().optional(),
      max_age: z.number().int().nonnegative().optional(),
    }).optional(),

    // Imágenes
    images: z.array(z.object({
      url: z.string().url(),
      alt: z.string().optional(),
      type: z.enum(['main', 'gallery', 'thumbnail']).default('main'),
    })).optional(),

    // URLs relacionadas
    ticket_url: z.string().url().optional(),
    event_url: z.string().url(),

    // Idioma del contenido
    language: z.string().length(2).default('es'),
  }),

  // Metadata de extracción
  extraction_metadata: z.object({
    method: z.string(),
    template_id: z.number().int().optional(),
    confidence: z.number().min(0).max(1),
    selectors_used: z.record(z.string()).optional(),
    processing_time_ms: z.number().int().optional(),
    warnings: z.array(z.string()).optional(),
  }),

  extracted_at: z.string().datetime().optional(),
});

type EventExtractedPayload = z.infer<typeof EventExtractedPayloadSchema>;
```

#### evt.event.duplicate

**Propósito:** Indica que el evento extraído ya existe en el sistema.

```typescript
// MESSAGE_TYPES.EVT_EVENT_DUPLICATE = 'evt.event.duplicate'

const EventDuplicatePayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  source_id: z.number().int().positive(),

  // Evento duplicado detectado
  duplicate_info: z.object({
    // ID del evento original
    original_event_id: z.number().int(),
    original_page_id: z.string().uuid().optional(),

    // Razón del duplicado
    reason: z.enum(['same_url', 'same_title_date', 'fuzzy_match', 'manual']),

    // Score de similitud (para fuzzy_match)
    similarity_score: z.number().min(0).max(1).optional(),

    // Campos que coinciden
    matching_fields: z.array(z.string()).optional(),
  }),

  detected_at: z.string().datetime().optional(),
});

type EventDuplicatePayload = z.infer<typeof EventDuplicatePayloadSchema>;
```

#### evt.event.extraction_failed

**Propósito:** Indica que la extracción de datos falló.

```typescript
// MESSAGE_TYPES.EVT_EVENT_EXTRACTION_FAILED = 'evt.event.extraction_failed'

const EventExtractionFailedPayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  source_id: z.number().int().positive(),

  // Detalles del error
  error: z.object({
    code: z.enum([
      'MISSING_REQUIRED_FIELD',   // Campo obligatorio no encontrado
      'INVALID_DATE_FORMAT',      // Fecha no parseable
      'SELECTOR_NOT_FOUND',       // Selector CSS no encontró elementos
      'TEMPLATE_ERROR',           // Error en template de extracción
      'PARSING_ERROR',            // Error general de parsing
      'VALIDATION_ERROR',         // Datos extraídos no pasan validación
      'UNKNOWN_ERROR',            // Error no categorizado
    ]),
    message: z.string(),
    details: z.object({
      missing_fields: z.array(z.string()).optional(),
      failed_selectors: z.array(z.string()).optional(),
      validation_errors: z.array(z.string()).optional(),
    }).optional(),
  }),

  // Datos parciales extraídos (si hay alguno)
  partial_data: z.record(z.unknown()).optional(),

  failed_at: z.string().datetime().optional(),
});

type EventExtractionFailedPayload = z.infer<typeof EventExtractionFailedPayloadSchema>;
```

---

### Dominio: Event (Persistencia)

#### evt.event.created

**Propósito:** Indica que un evento fue persistido en la base de datos.

```typescript
// MESSAGE_TYPES.EVT_EVENT_CREATED = 'evt.event.created'

const EventCreatedPayloadSchema = z.object({
  // IDs
  event_id: z.number().int().positive(),
  page_id: z.string().uuid(),
  tenant_id: z.string(),
  source_id: z.number().int().positive(),

  // Datos del evento creado
  event: z.object({
    title: z.string(),
    starts_at: z.string().datetime(),
    ends_at: z.string().datetime().optional(),
    url: z.string().url(),
    venue_id: z.number().int().optional(),
    organizer_id: z.number().int().optional(),
    event_category_id: z.number().int().optional(),
  }),

  // Metadata
  data_quality_score: z.number().min(0).max(1).optional(),

  created_at: z.string().datetime().optional(),
});

type EventCreatedPayload = z.infer<typeof EventCreatedPayloadSchema>;
```

#### evt.event.updated

**Propósito:** Indica que un evento existente fue actualizado.

```typescript
// MESSAGE_TYPES.EVT_EVENT_UPDATED = 'evt.event.updated'

const EventUpdatedPayloadSchema = z.object({
  // IDs
  event_id: z.number().int().positive(),
  page_id: z.string().uuid(),
  tenant_id: z.string(),
  source_id: z.number().int().positive(),

  // Campos actualizados
  updated_fields: z.array(z.string()),

  // Valores anteriores (para auditoría)
  previous_values: z.record(z.unknown()).optional(),

  // Valores nuevos
  new_values: z.record(z.unknown()),

  updated_at: z.string().datetime().optional(),
});

type EventUpdatedPayload = z.infer<typeof EventUpdatedPayloadSchema>;
```

---

### Dominio: Discovery

> **Nota:** Los contratos de discovery son **agnósticos de la estrategia**. El worker internamente usa Crawlee, pero los mensajes no exponen esta implementación.

#### cmd.source.discover

**Propósito:** Iniciar descubrimiento de URLs de un source usando una estrategia específica.

```typescript
// MESSAGE_TYPES.CMD_SOURCE_DISCOVER = 'cmd.source.discover'

const SourceDiscoverPayloadSchema = z.object({
  source_id: z.number().int().positive(),
  base_url: z.string().url(),
  tenant_id: z.string(),

  // Estrategia de descubrimiento
  strategy: z.enum([
    'sitemap',      // Usar sitemap.xml
    'link_crawl',   // Crawling de enlaces internos
    'rss_feed',     // Feeds RSS/Atom
    'url_pattern',  // Patrones de URL conocidos
    'hybrid',       // Combinación de estrategias
  ]).default('hybrid'),

  // Configuración común
  discovery_config: z.object({
    // Respetar robots.txt
    respect_robots_txt: z.boolean().default(true),

    // Límites
    max_urls: z.number().int().positive().default(1000),
    max_depth: z.number().int().positive().default(3),

    // Filtros de URL
    url_filters: z.object({
      include_patterns: z.array(z.string()).optional(), // Regex patterns
      exclude_patterns: z.array(z.string()).optional(),
    }).optional(),

    // Filtrar por tipos de contenido esperado
    content_type_filter: z.array(z.enum([
      'events',
      'venues',
      'organizers',
      'posts',
      'categories',
    ])).optional(),
  }).optional(),

  // Configuración específica por estrategia
  strategy_config: z.object({
    // Para sitemap
    sitemap_urls: z.array(z.string().url()).optional(),

    // Para link_crawl
    start_urls: z.array(z.string().url()).optional(),
    link_selector: z.string().optional(),

    // Para rss_feed
    feed_urls: z.array(z.string().url()).optional(),

    // Para url_pattern
    patterns: z.array(z.object({
      template: z.string(), // Ej: "/events/{year}/{month}"
      variables: z.record(z.array(z.string())).optional(),
    })).optional(),
  }).optional(),
});

type SourceDiscoverPayload = z.infer<typeof SourceDiscoverPayloadSchema>;
```

#### evt.discovery.urls_found

**Propósito:** Indica que se encontraron URLs durante el descubrimiento.

```typescript
// MESSAGE_TYPES.EVT_DISCOVERY_URLS_FOUND = 'evt.discovery.urls_found'

const DiscoveryUrlsFoundPayloadSchema = z.object({
  source_id: z.number().int().positive(),
  tenant_id: z.string(),
  discovery_run_id: z.number().int().positive(),

  // Estrategia usada
  strategy: z.enum(['sitemap', 'link_crawl', 'rss_feed', 'url_pattern', 'hybrid']),

  // Origen específico (si aplica)
  discovered_from: z.object({
    type: z.enum(['sitemap', 'page_link', 'rss_item', 'pattern']),
    url: z.string().url().optional(),
  }),

  // URLs descubiertas (batch)
  urls: z.array(z.object({
    url: z.string().url(),

    // Metadata opcional (depende de la fuente)
    lastmod: z.string().datetime().optional(),
    priority: z.number().min(0).max(1).optional(),
    changefreq: z.string().optional(),

    // Título/descripción si viene de RSS o link
    title: z.string().optional(),
  })),

  // Estadísticas del batch
  // Nota: duplicate_urls son URLs filtradas por Redis cache (ya existían en pages)
  batch_stats: z.object({
    total_in_batch: z.number().int(),    // URLs encontradas en esta iteración
    new_urls: z.number().int(),           // URLs nuevas (pasaron filtro Redis)
    duplicate_urls: z.number().int(),     // URLs conocidas (cache hit en Redis)
    filtered_urls: z.number().int(),      // URLs filtradas (robots, patrones, etc.)
  }),

  // Es el último batch?
  is_final_batch: z.boolean().default(false),

  discovered_at: z.string().datetime().optional(),
});

type DiscoveryUrlsFoundPayload = z.infer<typeof DiscoveryUrlsFoundPayloadSchema>;
```

#### evt.discovery.completed

**Propósito:** Indica que el descubrimiento finalizó exitosamente.

```typescript
// MESSAGE_TYPES.EVT_DISCOVERY_COMPLETED = 'evt.discovery.completed'

const DiscoveryCompletedPayloadSchema = z.object({
  source_id: z.number().int().positive(),
  tenant_id: z.string(),
  discovery_run_id: z.number().int().positive(),

  // Estrategia usada
  strategy: z.enum(['sitemap', 'link_crawl', 'rss_feed', 'url_pattern', 'hybrid']),

  // Estadísticas finales
  stats: z.object({
    total_urls_discovered: z.number().int(),   // Total URLs encontradas
    total_urls_queued: z.number().int(),       // URLs nuevas encoladas
    total_urls_filtered: z.number().int(),     // URLs filtradas (robots, patrones)
    total_urls_duplicate: z.number().int(),    // URLs duplicadas (Redis cache hits)
    cache_hit_rate: z.number().min(0).max(1).optional(), // % de duplicados
    pages_crawled: z.number().int().optional(),     // Para link_crawl
    sitemaps_processed: z.number().int().optional(), // Para sitemap
    feeds_processed: z.number().int().optional(),    // Para rss_feed
  }),

  // Duración
  duration_ms: z.number().int(),

  completed_at: z.string().datetime().optional(),
});

type DiscoveryCompletedPayload = z.infer<typeof DiscoveryCompletedPayloadSchema>;
```

#### evt.discovery.failed

**Propósito:** Indica que el descubrimiento falló.

```typescript
// MESSAGE_TYPES.EVT_DISCOVERY_FAILED = 'evt.discovery.failed'

const DiscoveryFailedPayloadSchema = z.object({
  source_id: z.number().int().positive(),
  tenant_id: z.string(),
  discovery_run_id: z.number().int().positive(),

  // Estrategia intentada
  strategy: z.enum(['sitemap', 'link_crawl', 'rss_feed', 'url_pattern', 'hybrid']),

  // Error
  error: z.object({
    code: z.enum([
      'SITEMAP_NOT_FOUND',       // No se encontró sitemap
      'SITEMAP_PARSE_ERROR',     // Error parseando sitemap
      'ROBOTS_BLOCKED',          // Bloqueado por robots.txt
      'NETWORK_ERROR',           // Error de red
      'TIMEOUT',                 // Timeout
      'RATE_LIMITED',            // Rate limiting
      'NO_URLS_FOUND',           // No se encontraron URLs
      'CONFIG_ERROR',            // Error de configuración
      'UNKNOWN_ERROR',           // Error desconocido
    ]),
    message: z.string(),
    details: z.record(z.unknown()).optional(),
  }),

  // URLs parcialmente descubiertas (si las hay)
  partial_stats: z.object({
    urls_discovered_before_failure: z.number().int(),
    urls_queued_before_failure: z.number().int(),
  }).optional(),

  failed_at: z.string().datetime().optional(),
});

type DiscoveryFailedPayload = z.infer<typeof DiscoveryFailedPayloadSchema>;
```

---

## Schemas Zod Completos

### Archivo: src/messages/classify/index.ts

```typescript
import { z } from 'zod';
import { EnvelopeSchemaV1 } from '../../envelope';

// ============================================================================
// cmd.page.classify
// ============================================================================
export const PageClassifyPayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  source_id: z.number().int().positive(),
  html: z.string(),
  content_hash: z.string().optional(),
  classification_config: z.object({
    method: z.enum(['rule_based', 'ml_model', 'hybrid']).default('rule_based'),
    min_confidence: z.number().min(0).max(1).default(0.7),
    rule_ids: z.array(z.number().int()).optional(),
    force_result: z.boolean().optional(),
  }).optional(),
});

export const PageClassifySchema = EnvelopeSchemaV1.extend({
  message_type: z.literal('cmd.page.classify'),
  payload: PageClassifyPayloadSchema,
});

export type PageClassifyPayload = z.infer<typeof PageClassifyPayloadSchema>;
export type PageClassifyMessage = z.infer<typeof PageClassifySchema>;

// ============================================================================
// evt.page.classified.event
// ============================================================================
export const PageClassifiedEventPayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  source_id: z.number().int().positive(),
  classification: z.object({
    is_event: z.literal(true),
    score: z.number().min(0).max(1),
    method: z.enum(['rule_based', 'ml_model', 'hybrid', 'manual']),
    reason: z.string().optional(),
    matched_rules: z.array(z.object({
      rule_id: z.number().int(),
      rule_name: z.string(),
      score_contribution: z.number(),
    })).optional(),
    preliminary_data: z.object({
      detected_title: z.string().optional(),
      detected_date: z.string().optional(),
      detected_schema_org: z.boolean().optional(),
    }).optional(),
  }),
  html: z.string(),
  content_hash: z.string().optional(),
  classified_at: z.string().datetime().optional(),
});

export const PageClassifiedEventSchema = EnvelopeSchemaV1.extend({
  message_type: z.literal('evt.page.classified.event'),
  payload: PageClassifiedEventPayloadSchema,
});

export type PageClassifiedEventPayload = z.infer<typeof PageClassifiedEventPayloadSchema>;
export type PageClassifiedEventMessage = z.infer<typeof PageClassifiedEventSchema>;

// ============================================================================
// evt.page.classified.other
// ============================================================================
export const PageClassifiedOtherPayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  source_id: z.number().int().positive(),
  classification: z.object({
    is_event: z.literal(false),
    score: z.number().min(0).max(1),
    method: z.enum(['rule_based', 'ml_model', 'hybrid', 'manual']),
    reason: z.string().optional(),
    detected_type: z.enum([
      'listing',
      'category',
      'search',
      'article',
      'static',
      'unknown'
    ]).optional(),
  }),
  classified_at: z.string().datetime().optional(),
});

export const PageClassifiedOtherSchema = EnvelopeSchemaV1.extend({
  message_type: z.literal('evt.page.classified.other'),
  payload: PageClassifiedOtherPayloadSchema,
});

export type PageClassifiedOtherPayload = z.infer<typeof PageClassifiedOtherPayloadSchema>;
export type PageClassifiedOtherMessage = z.infer<typeof PageClassifiedOtherSchema>;
```

### Archivo: src/messages/extract/index.ts

```typescript
import { z } from 'zod';
import { EnvelopeSchemaV1 } from '../../envelope';

// ============================================================================
// Schemas compartidos para extracción
// ============================================================================
const LocationSchema = z.object({
  name: z.string().optional(),
  address: z.string().optional(),
  city: z.string().optional(),
  region: z.string().optional(),
  country: z.string().default('ES'),
  postal_code: z.string().optional(),
  latitude: z.number().optional(),
  longitude: z.number().optional(),
});

const PriceSchema = z.object({
  type: z.enum(['free', 'paid', 'donation', 'variable']),
  amount: z.number().nonnegative().optional(),
  currency: z.string().length(3).default('EUR'),
  text: z.string().optional(),
});

const ImageSchema = z.object({
  url: z.string().url(),
  alt: z.string().optional(),
  type: z.enum(['main', 'gallery', 'thumbnail']).default('main'),
});

// ============================================================================
// cmd.event.extract
// ============================================================================
export const EventExtractPayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  source_id: z.number().int().positive(),
  html: z.string(),
  content_hash: z.string().optional(),
  extraction_config: z.object({
    technology_template_id: z.number().int().optional(),
    selector_overrides: z.record(z.string()).optional(),
    expected_language: z.string().length(2).default('es'),
    force_extraction: z.boolean().default(false),
  }).optional(),
  classification_hints: z.object({
    detected_title: z.string().optional(),
    detected_date: z.string().optional(),
    detected_schema_org: z.boolean().optional(),
  }).optional(),
});

export const EventExtractSchema = EnvelopeSchemaV1.extend({
  message_type: z.literal('cmd.event.extract'),
  payload: EventExtractPayloadSchema,
});

export type EventExtractPayload = z.infer<typeof EventExtractPayloadSchema>;
export type EventExtractMessage = z.infer<typeof EventExtractSchema>;

// ============================================================================
// evt.event.extracted
// ============================================================================
export const ExtractedEventDataSchema = z.object({
  title: z.string().min(1),
  starts_at: z.string().datetime(),
  description: z.string().optional(),
  ends_at: z.string().datetime().optional(),
  location: LocationSchema.optional(),
  organizer: z.object({
    name: z.string(),
    url: z.string().url().optional(),
  }).optional(),
  price: PriceSchema.optional(),
  categories: z.array(z.string()).optional(),
  age_group: z.object({
    name: z.string().optional(),
    min_age: z.number().int().nonnegative().optional(),
    max_age: z.number().int().nonnegative().optional(),
  }).optional(),
  images: z.array(ImageSchema).optional(),
  ticket_url: z.string().url().optional(),
  event_url: z.string().url(),
  language: z.string().length(2).default('es'),
});

export const EventExtractedPayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  source_id: z.number().int().positive(),
  extracted_event: ExtractedEventDataSchema,
  extraction_metadata: z.object({
    method: z.string(),
    template_id: z.number().int().optional(),
    confidence: z.number().min(0).max(1),
    selectors_used: z.record(z.string()).optional(),
    processing_time_ms: z.number().int().optional(),
    warnings: z.array(z.string()).optional(),
  }),
  extracted_at: z.string().datetime().optional(),
});

export const EventExtractedSchema = EnvelopeSchemaV1.extend({
  message_type: z.literal('evt.event.extracted'),
  payload: EventExtractedPayloadSchema,
});

export type ExtractedEventData = z.infer<typeof ExtractedEventDataSchema>;
export type EventExtractedPayload = z.infer<typeof EventExtractedPayloadSchema>;
export type EventExtractedMessage = z.infer<typeof EventExtractedSchema>;

// ============================================================================
// evt.event.duplicate
// ============================================================================
export const EventDuplicatePayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  source_id: z.number().int().positive(),
  duplicate_info: z.object({
    original_event_id: z.number().int(),
    original_page_id: z.string().uuid().optional(),
    reason: z.enum(['same_url', 'same_title_date', 'fuzzy_match', 'manual']),
    similarity_score: z.number().min(0).max(1).optional(),
    matching_fields: z.array(z.string()).optional(),
  }),
  detected_at: z.string().datetime().optional(),
});

export const EventDuplicateSchema = EnvelopeSchemaV1.extend({
  message_type: z.literal('evt.event.duplicate'),
  payload: EventDuplicatePayloadSchema,
});

export type EventDuplicatePayload = z.infer<typeof EventDuplicatePayloadSchema>;
export type EventDuplicateMessage = z.infer<typeof EventDuplicateSchema>;

// ============================================================================
// evt.event.extraction_failed
// ============================================================================
export const EventExtractionFailedPayloadSchema = z.object({
  page_id: z.string().uuid(),
  url: z.string().url(),
  tenant_id: z.string(),
  source_id: z.number().int().positive(),
  error: z.object({
    code: z.enum([
      'MISSING_REQUIRED_FIELD',
      'INVALID_DATE_FORMAT',
      'SELECTOR_NOT_FOUND',
      'TEMPLATE_ERROR',
      'PARSING_ERROR',
      'VALIDATION_ERROR',
      'UNKNOWN_ERROR',
    ]),
    message: z.string(),
    details: z.object({
      missing_fields: z.array(z.string()).optional(),
      failed_selectors: z.array(z.string()).optional(),
      validation_errors: z.array(z.string()).optional(),
    }).optional(),
  }),
  partial_data: z.record(z.unknown()).optional(),
  failed_at: z.string().datetime().optional(),
});

export const EventExtractionFailedSchema = EnvelopeSchemaV1.extend({
  message_type: z.literal('evt.event.extraction_failed'),
  payload: EventExtractionFailedPayloadSchema,
});

export type EventExtractionFailedPayload = z.infer<typeof EventExtractionFailedPayloadSchema>;
export type EventExtractionFailedMessage = z.infer<typeof EventExtractionFailedSchema>;
```

### Archivo: src/messages/discovery/index.ts

```typescript
import { z } from 'zod';
import { EnvelopeSchemaV1 } from '../../envelope';

// ============================================================================
// Schemas compartidos para discovery
// ============================================================================
const DiscoveryStrategySchema = z.enum([
  'sitemap',
  'link_crawl',
  'rss_feed',
  'url_pattern',
  'hybrid',
]);

export type DiscoveryStrategy = z.infer<typeof DiscoveryStrategySchema>;

// ============================================================================
// cmd.source.discover
// ============================================================================
export const SourceDiscoverPayloadSchema = z.object({
  source_id: z.number().int().positive(),
  base_url: z.string().url(),
  tenant_id: z.string(),
  strategy: DiscoveryStrategySchema.default('hybrid'),
  discovery_config: z.object({
    respect_robots_txt: z.boolean().default(true),
    max_urls: z.number().int().positive().default(1000),
    max_depth: z.number().int().positive().default(3),
    url_filters: z.object({
      include_patterns: z.array(z.string()).optional(),
      exclude_patterns: z.array(z.string()).optional(),
    }).optional(),
    content_type_filter: z.array(z.enum([
      'events',
      'venues',
      'organizers',
      'posts',
      'categories',
    ])).optional(),
  }).optional(),
  strategy_config: z.object({
    sitemap_urls: z.array(z.string().url()).optional(),
    start_urls: z.array(z.string().url()).optional(),
    link_selector: z.string().optional(),
    feed_urls: z.array(z.string().url()).optional(),
    patterns: z.array(z.object({
      template: z.string(),
      variables: z.record(z.array(z.string())).optional(),
    })).optional(),
  }).optional(),
});

export const SourceDiscoverSchema = EnvelopeSchemaV1.extend({
  message_type: z.literal('cmd.source.discover'),
  payload: SourceDiscoverPayloadSchema,
});

export type SourceDiscoverPayload = z.infer<typeof SourceDiscoverPayloadSchema>;
export type SourceDiscoverMessage = z.infer<typeof SourceDiscoverSchema>;

// ============================================================================
// evt.discovery.urls_found
// ============================================================================
export const DiscoveryUrlsFoundPayloadSchema = z.object({
  source_id: z.number().int().positive(),
  tenant_id: z.string(),
  discovery_run_id: z.number().int().positive(),
  strategy: DiscoveryStrategySchema,
  discovered_from: z.object({
    type: z.enum(['sitemap', 'page_link', 'rss_item', 'pattern']),
    url: z.string().url().optional(),
  }),
  urls: z.array(z.object({
    url: z.string().url(),
    lastmod: z.string().datetime().optional(),
    priority: z.number().min(0).max(1).optional(),
    changefreq: z.string().optional(),
    title: z.string().optional(),
  })),
  batch_stats: z.object({
    total_in_batch: z.number().int(),
    new_urls: z.number().int(),
    duplicate_urls: z.number().int(),
    filtered_urls: z.number().int(),
  }),
  is_final_batch: z.boolean().default(false),
  discovered_at: z.string().datetime().optional(),
});

export const DiscoveryUrlsFoundSchema = EnvelopeSchemaV1.extend({
  message_type: z.literal('evt.discovery.urls_found'),
  payload: DiscoveryUrlsFoundPayloadSchema,
});

export type DiscoveryUrlsFoundPayload = z.infer<typeof DiscoveryUrlsFoundPayloadSchema>;
export type DiscoveryUrlsFoundMessage = z.infer<typeof DiscoveryUrlsFoundSchema>;

// ============================================================================
// evt.discovery.completed
// ============================================================================
export const DiscoveryCompletedPayloadSchema = z.object({
  source_id: z.number().int().positive(),
  tenant_id: z.string(),
  discovery_run_id: z.number().int().positive(),
  strategy: DiscoveryStrategySchema,
  stats: z.object({
    total_urls_discovered: z.number().int(),
    total_urls_queued: z.number().int(),
    total_urls_filtered: z.number().int(),
    total_urls_duplicate: z.number().int(),
    cache_hit_rate: z.number().min(0).max(1).optional(), // % duplicados via Redis
    pages_crawled: z.number().int().optional(),
    sitemaps_processed: z.number().int().optional(),
    feeds_processed: z.number().int().optional(),
  }),
  duration_ms: z.number().int(),
  completed_at: z.string().datetime().optional(),
});

export const DiscoveryCompletedSchema = EnvelopeSchemaV1.extend({
  message_type: z.literal('evt.discovery.completed'),
  payload: DiscoveryCompletedPayloadSchema,
});

export type DiscoveryCompletedPayload = z.infer<typeof DiscoveryCompletedPayloadSchema>;
export type DiscoveryCompletedMessage = z.infer<typeof DiscoveryCompletedSchema>;

// ============================================================================
// evt.discovery.failed
// ============================================================================
export const DiscoveryFailedPayloadSchema = z.object({
  source_id: z.number().int().positive(),
  tenant_id: z.string(),
  discovery_run_id: z.number().int().positive(),
  strategy: DiscoveryStrategySchema,
  error: z.object({
    code: z.enum([
      'SITEMAP_NOT_FOUND',
      'SITEMAP_PARSE_ERROR',
      'ROBOTS_BLOCKED',
      'NETWORK_ERROR',
      'TIMEOUT',
      'RATE_LIMITED',
      'NO_URLS_FOUND',
      'CONFIG_ERROR',
      'UNKNOWN_ERROR',
    ]),
    message: z.string(),
    details: z.record(z.unknown()).optional(),
  }),
  partial_stats: z.object({
    urls_discovered_before_failure: z.number().int(),
    urls_queued_before_failure: z.number().int(),
  }).optional(),
  failed_at: z.string().datetime().optional(),
});

export const DiscoveryFailedSchema = EnvelopeSchemaV1.extend({
  message_type: z.literal('evt.discovery.failed'),
  payload: DiscoveryFailedPayloadSchema,
});

export type DiscoveryFailedPayload = z.infer<typeof DiscoveryFailedPayloadSchema>;
export type DiscoveryFailedMessage = z.infer<typeof DiscoveryFailedSchema>;
```

### Archivo: src/messages/discovery/builders.ts

```typescript
import { v4 as uuidv4 } from 'uuid';
import type {
  SourceDiscoverPayload,
  DiscoveryUrlsFoundPayload,
  DiscoveryCompletedPayload,
  DiscoveryFailedPayload,
} from './index';
import type { EnvelopeV1 } from '../../envelope';

interface BuilderOptions {
  correlation_id?: string;
  causation_id?: string;
}

// ============================================================================
// buildSourceDiscoverCommand
// ============================================================================
export function buildSourceDiscoverCommand(
  payload: SourceDiscoverPayload,
  options?: BuilderOptions
): EnvelopeV1<SourceDiscoverPayload> {
  return {
    message_id: uuidv4(),
    message_type: 'cmd.source.discover',
    schema_version: 1,
    occurred_at: new Date().toISOString(),
    correlation_id: options?.correlation_id ?? uuidv4(),
    causation_id: options?.causation_id,
    tenant_id: payload.tenant_id,
    aggregate: {
      type: 'source',
      id: String(payload.source_id),
    },
    payload,
  };
}

// ============================================================================
// buildDiscoveryUrlsFoundEvent
// ============================================================================
export function buildDiscoveryUrlsFoundEvent(
  payload: DiscoveryUrlsFoundPayload,
  options?: BuilderOptions
): EnvelopeV1<DiscoveryUrlsFoundPayload> {
  return {
    message_id: uuidv4(),
    message_type: 'evt.discovery.urls_found',
    schema_version: 1,
    occurred_at: new Date().toISOString(),
    correlation_id: options?.correlation_id ?? uuidv4(),
    causation_id: options?.causation_id,
    tenant_id: payload.tenant_id,
    aggregate: {
      type: 'discovery_run',
      id: String(payload.discovery_run_id),
    },
    payload: {
      ...payload,
      discovered_at: payload.discovered_at ?? new Date().toISOString(),
    },
  };
}

// ============================================================================
// buildDiscoveryCompletedEvent
// ============================================================================
export function buildDiscoveryCompletedEvent(
  payload: DiscoveryCompletedPayload,
  options?: BuilderOptions
): EnvelopeV1<DiscoveryCompletedPayload> {
  return {
    message_id: uuidv4(),
    message_type: 'evt.discovery.completed',
    schema_version: 1,
    occurred_at: new Date().toISOString(),
    correlation_id: options?.correlation_id ?? uuidv4(),
    causation_id: options?.causation_id,
    tenant_id: payload.tenant_id,
    aggregate: {
      type: 'discovery_run',
      id: String(payload.discovery_run_id),
    },
    payload: {
      ...payload,
      completed_at: payload.completed_at ?? new Date().toISOString(),
    },
  };
}

// ============================================================================
// buildDiscoveryFailedEvent
// ============================================================================
export function buildDiscoveryFailedEvent(
  payload: DiscoveryFailedPayload,
  options?: BuilderOptions
): EnvelopeV1<DiscoveryFailedPayload> {
  return {
    message_id: uuidv4(),
    message_type: 'evt.discovery.failed',
    schema_version: 1,
    occurred_at: new Date().toISOString(),
    correlation_id: options?.correlation_id ?? uuidv4(),
    causation_id: options?.causation_id,
    tenant_id: payload.tenant_id,
    aggregate: {
      type: 'discovery_run',
      id: String(payload.discovery_run_id),
    },
    payload: {
      ...payload,
      failed_at: payload.failed_at ?? new Date().toISOString(),
    },
  };
}
```

---

## Builders Recomendados

### Archivo: src/messages/classify/builders.ts

```typescript
import { v4 as uuidv4 } from 'uuid';
import type { PageClassifyPayload, PageClassifiedEventPayload, PageClassifiedOtherPayload } from './index';
import type { EnvelopeV1 } from '../../envelope';

interface BuilderOptions {
  correlation_id?: string;
  causation_id?: string;
}

// ============================================================================
// buildPageClassifyCommand
// ============================================================================
export function buildPageClassifyCommand(
  payload: PageClassifyPayload,
  options?: BuilderOptions
): EnvelopeV1<PageClassifyPayload> {
  return {
    message_id: uuidv4(),
    message_type: 'cmd.page.classify',
    schema_version: 1,
    occurred_at: new Date().toISOString(),
    correlation_id: options?.correlation_id ?? uuidv4(),
    causation_id: options?.causation_id,
    tenant_id: payload.tenant_id,
    aggregate: {
      type: 'page',
      id: payload.page_id,
    },
    payload,
  };
}

// ============================================================================
// buildPageClassifiedEventEvent
// ============================================================================
export function buildPageClassifiedEventEvent(
  payload: PageClassifiedEventPayload,
  options?: BuilderOptions
): EnvelopeV1<PageClassifiedEventPayload> {
  return {
    message_id: uuidv4(),
    message_type: 'evt.page.classified.event',
    schema_version: 1,
    occurred_at: new Date().toISOString(),
    correlation_id: options?.correlation_id ?? uuidv4(),
    causation_id: options?.causation_id,
    tenant_id: payload.tenant_id,
    aggregate: {
      type: 'page',
      id: payload.page_id,
    },
    payload: {
      ...payload,
      classified_at: payload.classified_at ?? new Date().toISOString(),
    },
  };
}

// ============================================================================
// buildPageClassifiedOtherEvent
// ============================================================================
export function buildPageClassifiedOtherEvent(
  payload: PageClassifiedOtherPayload,
  options?: BuilderOptions
): EnvelopeV1<PageClassifiedOtherPayload> {
  return {
    message_id: uuidv4(),
    message_type: 'evt.page.classified.other',
    schema_version: 1,
    occurred_at: new Date().toISOString(),
    correlation_id: options?.correlation_id ?? uuidv4(),
    causation_id: options?.causation_id,
    tenant_id: payload.tenant_id,
    aggregate: {
      type: 'page',
      id: payload.page_id,
    },
    payload: {
      ...payload,
      classified_at: payload.classified_at ?? new Date().toISOString(),
    },
  };
}
```

---

## Flujo de Mensajes

### Diagrama de Secuencia Completo

```
┌──────┐    ┌─────────┐    ┌────────┐    ┌──────────┐    ┌──────────┐    ┌─────────┐
│ API  │    │ Event   │    │Scraping│    │Classifi- │    │Extraction│    │  Event  │
│      │    │Processor│    │ Worker │    │  cation  │    │  Worker  │    │Processor│
└──┬───┘    └────┬────┘    └───┬────┘    └────┬─────┘    └────┬─────┘    └────┬────┘
   │             │             │              │               │               │
   │ cmd.page.   │             │              │               │               │
   │ process_    │             │              │               │               │
   │ request     │             │              │               │               │
   │────────────>│             │              │               │               │
   │             │             │              │               │               │
   │             │ evt.page.   │              │               │               │
   │             │ processing_ │              │               │               │
   │             │ started     │              │               │               │
   │<────────────│             │              │               │               │
   │             │             │              │               │               │
   │             │ cmd.scrape. │              │               │               │
   │             │ page.       │              │               │               │
   │             │ requested   │              │               │               │
   │             │────────────>│              │               │               │
   │             │             │              │               │               │
   │             │             │ evt.scrape.  │               │               │
   │             │             │ page.        │               │               │
   │             │             │ completed    │               │               │
   │             │<────────────│              │               │               │
   │             │             │              │               │               │
   │             │ cmd.page.   │              │               │               │
   │             │ classify    │              │               │               │
   │             │────────────────────────────>               │               │
   │             │             │              │               │               │
   │             │             │              │ evt.page.     │               │
   │             │             │              │ classified.   │               │
   │             │             │              │ event         │               │
   │             │<───────────────────────────│               │               │
   │             │             │              │               │               │
   │             │ cmd.event.  │              │               │               │
   │             │ extract     │              │               │               │
   │             │────────────────────────────────────────────>               │
   │             │             │              │               │               │
   │             │             │              │               │ evt.event.    │
   │             │             │              │               │ extracted     │
   │             │<────────────────────────────────────────────               │
   │             │             │              │               │               │
   │             │                            PERSISTE EN BD                  │
   │             │────────────────────────────────────────────────────────────>
   │             │             │              │               │               │
   │             │             │              │               │ evt.event.    │
   │             │             │              │               │ created       │
   │<────────────────────────────────────────────────────────────────────────│
   │             │             │              │               │               │
```

### Flujo de correlation_id y causation_id

```typescript
// 1. API crea el comando inicial
const cmd1 = {
  message_id: 'msg-001',
  correlation_id: 'corr-abc',  // Nuevo correlation_id
  causation_id: undefined,      // Sin causa (es el origen)
  message_type: 'cmd.page.process_request',
  // ...
};

// 2. Event Processor emite comando de scraping
const cmd2 = {
  message_id: 'msg-002',
  correlation_id: 'corr-abc',  // MISMO correlation_id
  causation_id: 'msg-001',     // Causado por cmd1
  message_type: 'cmd.scrape.page.requested',
  // ...
};

// 3. Scraping Worker emite evento de completado
const evt1 = {
  message_id: 'msg-003',
  correlation_id: 'corr-abc',  // MISMO correlation_id
  causation_id: 'msg-002',     // Causado por cmd2
  message_type: 'evt.scrape.page.completed',
  // ...
};

// 4. Event Processor emite comando de clasificación
const cmd3 = {
  message_id: 'msg-004',
  correlation_id: 'corr-abc',  // MISMO correlation_id
  causation_id: 'msg-003',     // Causado por evt1
  message_type: 'cmd.page.classify',
  // ...
};

// ... y así sucesivamente
```

---

## Guía de Implementación

### 1. Registrar Nuevos Schemas en Registry

```typescript
// src/registry/index.ts
import { MessageRegistry } from './MessageRegistry';

// Importar todos los schemas de payload
import { PageClassifyPayloadSchema, PageClassifiedEventPayloadSchema, PageClassifiedOtherPayloadSchema } from '../messages/classify';
import { EventExtractPayloadSchema, EventExtractedPayloadSchema, EventDuplicatePayloadSchema, EventExtractionFailedPayloadSchema } from '../messages/extract';

export const registry = new MessageRegistry();

// Registrar schemas de clasificación
registry.register({
  message_type: 'cmd.page.classify',
  schema_version: 1,
  schema: PageClassifyPayloadSchema,
});

registry.register({
  message_type: 'evt.page.classified.event',
  schema_version: 1,
  schema: PageClassifiedEventPayloadSchema,
});

registry.register({
  message_type: 'evt.page.classified.other',
  schema_version: 1,
  schema: PageClassifiedOtherPayloadSchema,
});

// Registrar schemas de extracción
registry.register({
  message_type: 'cmd.event.extract',
  schema_version: 1,
  schema: EventExtractPayloadSchema,
});

registry.register({
  message_type: 'evt.event.extracted',
  schema_version: 1,
  schema: EventExtractedPayloadSchema,
});

registry.register({
  message_type: 'evt.event.duplicate',
  schema_version: 1,
  schema: EventDuplicatePayloadSchema,
});

registry.register({
  message_type: 'evt.event.extraction_failed',
  schema_version: 1,
  schema: EventExtractionFailedPayloadSchema,
});

// Registrar schemas de discovery
import {
  SourceDiscoverPayloadSchema,
  DiscoveryUrlsFoundPayloadSchema,
  DiscoveryCompletedPayloadSchema,
  DiscoveryFailedPayloadSchema,
} from '../messages/discovery';

registry.register({
  message_type: 'cmd.source.discover',
  schema_version: 1,
  schema: SourceDiscoverPayloadSchema,
});

registry.register({
  message_type: 'evt.discovery.urls_found',
  schema_version: 1,
  schema: DiscoveryUrlsFoundPayloadSchema,
});

registry.register({
  message_type: 'evt.discovery.completed',
  schema_version: 1,
  schema: DiscoveryCompletedPayloadSchema,
});

registry.register({
  message_type: 'evt.discovery.failed',
  schema_version: 1,
  schema: DiscoveryFailedPayloadSchema,
});

export { registry };
```

### 2. Actualizar MESSAGE_TYPES

```typescript
// src/messages/constants.ts
export const MESSAGE_TYPES = {
  // Existentes
  CMD_PAGE_PROCESS_REQUEST: 'cmd.page.process_request',
  EVT_PAGE_PROCESSING_STARTED: 'evt.page.processing_started',
  EVT_PAGE_PROCESSED: 'evt.page.processed',
  EVT_PAGE_FAILED: 'evt.page.failed',

  CMD_SCRAPE_PAGE_REQUESTED: 'cmd.scrape.page.requested',
  EVT_SCRAPE_PAGE_COMPLETED: 'evt.scrape.page.completed',
  EVT_SCRAPE_PAGE_FAILED: 'evt.scrape.page.failed',

  // Nuevos - Clasificación
  CMD_PAGE_CLASSIFY: 'cmd.page.classify',
  EVT_PAGE_CLASSIFIED_EVENT: 'evt.page.classified.event',
  EVT_PAGE_CLASSIFIED_OTHER: 'evt.page.classified.other',

  // Nuevos - Extracción
  CMD_EVENT_EXTRACT: 'cmd.event.extract',
  EVT_EVENT_EXTRACTED: 'evt.event.extracted',
  EVT_EVENT_DUPLICATE: 'evt.event.duplicate',
  EVT_EVENT_EXTRACTION_FAILED: 'evt.event.extraction_failed',

  // Nuevos - Persistencia
  EVT_EVENT_CREATED: 'evt.event.created',
  EVT_EVENT_UPDATED: 'evt.event.updated',

  // Nuevos - Discovery (agnóstico de estrategia)
  CMD_SOURCE_DISCOVER: 'cmd.source.discover',
  EVT_DISCOVERY_URLS_FOUND: 'evt.discovery.urls_found',
  EVT_DISCOVERY_COMPLETED: 'evt.discovery.completed',
  EVT_DISCOVERY_FAILED: 'evt.discovery.failed',
} as const;

export type MessageType = typeof MESSAGE_TYPES[keyof typeof MESSAGE_TYPES];
```

### 3. Exportar desde index.ts

```typescript
// src/index.ts

// Envelope
export * from './envelope';

// Registry
export * from './registry';

// Constantes
export { MESSAGE_TYPES, type MessageType } from './messages/constants';

// Mensajes existentes
export * from './messages/pages';
export * from './messages/scrape';

// Nuevos mensajes
export * from './messages/classify';
export * from './messages/extract';
export * from './messages/event';
export * from './messages/discovery';

// Errores
export * from './errors';
```

---

## Referencias

- [Arquitectura del Proyecto](./ARCHITECTURE.md)
- [Migraciones de Base de Datos](./MIGRATIONS.md)
- [urbanmoop-contracts README](https://github.com/cruizmol/urbanmoop-contracts)
