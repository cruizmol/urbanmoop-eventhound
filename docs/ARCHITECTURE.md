# Eventhound - Arquitectura del Proyecto

## Índice

1. [Visión General](#visión-general)
2. [Stack Tecnológico](#stack-tecnológico)
3. [Arquitectura Event-Driven](#arquitectura-event-driven)
4. [Sistema de Discovery](#sistema-de-discovery)
5. [Sistema de Deduplicación Rápida](#sistema-de-deduplicación-rápida)
6. [Flujo de Procesamiento](#flujo-de-procesamiento)
7. [Servicios y Componentes](#servicios-y-componentes)
8. [Estructura de Directorios](#estructura-de-directorios)
9. [Integración con Crawlee](#integración-con-crawlee)
10. [Integración con urbanmoop-contracts](#integración-con-urbanmoop-contracts)
11. [Sistema de Configuración por Capas](#sistema-de-configuración-por-capas)
12. [Base de Datos](#base-de-datos)
13. [Configuración de Entorno](#configuración-de-entorno)

---

## Visión General

**Eventhound** es una plataforma de agregación de eventos culturales que utiliza web scraping inteligente para descubrir, extraer y normalizar información de eventos desde múltiples fuentes web.

### Objetivos Principales

- **Descubrimiento flexible de URLs** mediante múltiples estrategias (sitemap, link crawling, feeds, patrones)
- Clasificación inteligente de páginas (evento vs no-evento)
- Extracción de datos estructurados según configuraciones por tecnología/CMS
- Normalización y almacenamiento de eventos
- Soporte multilingüe con sistema de traducciones

### Principios de Diseño

| Principio | Descripción |
|-----------|-------------|
| **Event-Driven** | Comunicación asíncrona mediante mensajes (commands/events) |
| **Single Writer** | Solo el Event Processor escribe en la base de datos |
| **Contratos Agnósticos** | Los mensajes no exponen detalles de implementación interna |
| **Configuración por Capas** | Templates reutilizables con overrides específicos por sitio |
| **Escalabilidad Horizontal** | Workers stateless que pueden escalar independientemente |
| **Discovery Resiliente** | Múltiples estrategias de descubrimiento con fallback automático |

---

## Stack Tecnológico

### Core

| Componente | Tecnología | Versión | Propósito |
|------------|------------|---------|-----------|
| **Runtime** | Node.js | LTS (20.x+) | Entorno de ejecución |
| **Lenguaje** | TypeScript | 5.x | Tipado estático |
| **Base de Datos** | PostgreSQL | 15+ | Almacenamiento principal |
| **Message Broker** | RabbitMQ | 3.12+ | Cola de mensajes |
| **Cache** | Redis | 7.x | Caché y rate limiting |

### Librerías Principales

| Librería | Propósito |
|----------|-----------|
| **Crawlee** | Motor de web scraping y discovery (HTTP + Browser) |
| **Zod** | Validación de schemas en runtime |
| **@urbanmoop/contracts** | Contratos de mensajería compartidos |
| **Drizzle ORM** | ORM para PostgreSQL |
| **Playwright** | Browser automation (via Crawlee) |

### Infraestructura

| Servicio | Tecnología | Propósito |
|----------|------------|-----------|
| **Contenedores** | Docker | Empaquetado de servicios |
| **Orquestación** | Kubernetes / Docker Compose | Despliegue y escalado |
| **CI/CD** | GitHub Actions | Integración y despliegue continuo |
| **Monitoreo** | Prometheus + Grafana | Métricas y alertas |

---

## Arquitectura Event-Driven

### Diagrama General

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        ARQUITECTURA EVENT-DRIVEN EVENTHOUND                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│    ┌──────────────┐                                                             │
│    │   API/UI     │                                                             │
│    │   Gateway    │                                                             │
│    └──────┬───────┘                                                             │
│           │ cmd.source.discover / cmd.page.process_request                      │
│           ▼                                                                      │
│    ┌─────────────────────────────────────────────────────────────────────────┐  │
│    │                         MESSAGE BROKER (RabbitMQ)                        │  │
│    │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │  │
│    │  │  discovery  │  │   scrape    │  │  classify   │  │   extract   │    │  │
│    │  │  .commands  │  │  .commands  │  │  .commands  │  │  .commands  │    │  │
│    │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │  │
│    └─────────────────────────────────────────────────────────────────────────┘  │
│           │                    │                 │                │             │
│           ▼                    ▼                 ▼                ▼             │
│    ┌─────────────┐      ┌─────────────┐   ┌─────────────┐  ┌─────────────┐    │
│    │  Discovery  │      │   Scraping  │   │ Classifica- │  │ Extraction  │    │
│    │   Worker    │      │   Worker    │   │ tion Worker │  │   Worker    │    │
│    │  (Crawlee)  │      │  (Crawlee)  │   │  (ML/Rules) │  │  (Parsing)  │    │
│    │             │      │             │   │             │  │             │    │
│    │ NO escribe  │      │ NO escribe  │   │ NO escribe  │  │ NO escribe  │    │
│    │ en BD       │      │ en BD       │   │ en BD       │  │ en BD       │    │
│    └──────┬──────┘      └──────┬──────┘   └──────┬──────┘  └──────┬──────┘    │
│           │                    │                 │                │             │
│           └────────────────────┴─────────────────┴────────────────┘             │
│                                      │                                          │
│                                      ▼                                          │
│                            ┌─────────────────┐                                  │
│                            │ Event Processor │                                  │
│                            │ ─────────────── │                                  │
│                            │  ÚNICO QUE      │                                  │
│                            │  ESCRIBE EN BD  │                                  │
│                            └────────┬────────┘                                  │
│                                     │                                           │
│                                     ▼                                           │
│                            ┌─────────────────┐                                  │
│                            │   PostgreSQL    │                                  │
│                            │  (webscraping)  │                                  │
│                            └─────────────────┘                                  │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Principio Single Writer

**CRÍTICO**: Solo el **Event Processor** tiene permisos de escritura en la base de datos.

| Servicio | Lee BD | Escribe BD | Publica Eventos |
|----------|--------|------------|-----------------|
| API Gateway | ✅ | ❌ | ✅ |
| Discovery Worker | ❌ | ❌ | ✅ |
| Scraping Worker | ❌ | ❌ | ✅ |
| Classification Worker | ❌ | ❌ | ✅ |
| Extraction Worker | ❌ | ❌ | ✅ |
| **Event Processor** | ✅ | ✅ | ✅ |

### Tipos de Mensajes

#### Commands (Intención de acción)
```
cmd.<aggregate>.<action>
```
- `cmd.source.discover` - Descubrir URLs de un source
- `cmd.page.process_request` - Solicitar procesamiento de página
- `cmd.page.classify` - Solicitar clasificación
- `cmd.event.extract` - Solicitar extracción de datos

#### Events (Hechos ocurridos)
```
evt.<aggregate>.<past_participle>
```
- `evt.discovery.urls_found` - URLs descubiertas
- `evt.scrape.page.completed` - Scraping completado
- `evt.page.classified` - Página clasificada
- `evt.event.extracted` - Datos de evento extraídos
- `evt.event.created` - Evento persistido en BD

---

## Sistema de Discovery

### Problema

No todos los sitios web tienen sitemap o lo exponen públicamente. Eventhound necesita múltiples estrategias de descubrimiento para ser resiliente.

### Estrategias Soportadas

| Estrategia | Descripción | Cuándo usar | Soporte Crawlee |
|------------|-------------|-------------|-----------------|
| **Sitemap** | Parsear sitemap.xml desde robots.txt | Sitios con sitemap público | `Sitemap.load()` + `RobotsFile` |
| **Link Crawling** | Seguir enlaces desde páginas semilla | Sitios sin sitemap | `enqueueLinks()` |
| **RSS/Atom Feeds** | Parsear feeds de eventos | Sitios con feeds | `CheerioCrawler` + XML parser |
| **URL Patterns** | Generar URLs predecibles | URLs estructuradas (`/eventos/2026/01/`) | `crawler.addRequests()` |
| **Hybrid** | Combinar múltiples estrategias | Maximizar cobertura | Todas las anteriores |

### Diagrama de Discovery

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         SISTEMA DE DISCOVERY UNIFICADO                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  cmd.source.discover                                                            │
│         │                                                                        │
│         ▼                                                                        │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │                        DISCOVERY WORKER (Crawlee)                         │   │
│  │                                                                           │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐     │   │
│  │  │  discovery_config (desde source_configurations)                  │     │   │
│  │  │  {                                                               │     │   │
│  │  │    "primary_strategy": "sitemap|crawl|feed|pattern|hybrid",     │     │   │
│  │  │    "fallback_enabled": true,                                     │     │   │
│  │  │    "sitemap": { ... },                                           │     │   │
│  │  │    "crawl": { "seed_urls": [...], "globs": [...] },             │     │   │
│  │  │    "feed": { "urls": [...] },                                    │     │   │
│  │  │    "pattern": { "template": "...", "params": {...} }            │     │   │
│  │  │  }                                                               │     │   │
│  │  └─────────────────────────────────────────────────────────────────┘     │   │
│  │                              │                                            │   │
│  │         ┌────────────────────┼────────────────────┐                      │   │
│  │         ▼                    ▼                    ▼                      │   │
│  │  ┌────────────┐      ┌────────────┐      ┌────────────┐                 │   │
│  │  │  Sitemap   │      │   Link     │      │   Feed/    │                 │   │
│  │  │  Strategy  │      │  Crawling  │      │  Pattern   │                 │   │
│  │  │            │      │  Strategy  │      │  Strategy  │                 │   │
│  │  │ RobotsFile │      │            │      │            │                 │   │
│  │  │ Sitemap.   │      │ enqueue    │      │ Cheerio    │                 │   │
│  │  │ load()     │      │ Links()    │      │ Crawler    │                 │   │
│  │  └─────┬──────┘      └─────┬──────┘      └─────┬──────┘                 │   │
│  │        │                   │                   │                         │   │
│  │        └───────────────────┴───────────────────┘                         │   │
│  │                            │                                              │   │
│  │                            ▼                                              │   │
│  │                   ┌─────────────────┐                                    │   │
│  │                   │   Deduplicate   │                                    │   │
│  │                   │   & Filter      │                                    │   │
│  │                   │   (RequestQueue)│                                    │   │
│  │                   └────────┬────────┘                                    │   │
│  │                            │                                              │   │
│  └────────────────────────────┼──────────────────────────────────────────────┘   │
│                               │                                                  │
│                               ▼                                                  │
│                    evt.discovery.urls_found                                      │
│                    (batch de URLs descubiertas)                                  │
│                               │                                                  │
│                               ▼                                                  │
│                       Event Processor                                            │
│                       (persiste en BD)                                           │
│                               │                                                  │
│                               ▼                                                  │
│                    cmd.scrape.page.requested                                     │
│                    (para cada URL nueva)                                         │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Configuración de Discovery por Source

```typescript
interface DiscoveryConfig {
  // Estrategia principal
  primary_strategy: 'sitemap' | 'crawl' | 'feed' | 'pattern' | 'hybrid';

  // Habilitar fallback si la estrategia principal falla o no encuentra URLs
  fallback_enabled: boolean;

  // Configuración de Sitemap
  sitemap?: {
    enabled: boolean;
    // URLs específicas (null = auto-discover desde robots.txt)
    urls?: string[] | null;
    // Filtrar por tipos de contenido en sitemap
    content_type_filter?: ('events' | 'venues' | 'posts')[];
  };

  // Configuración de Link Crawling
  crawl?: {
    enabled: boolean;
    // URLs semilla para empezar el crawling
    seed_urls: string[];
    // Profundidad máxima de enlaces a seguir
    max_depth: number;
    // Estrategia de Crawlee
    strategy: 'same-hostname' | 'same-domain' | 'same-origin';
    // Patrones de URLs a incluir (globs)
    include_globs: string[];
    // Patrones de URLs a excluir (globs)
    exclude_globs: string[];
    // Máximo de URLs a descubrir
    max_urls?: number;
  };

  // Configuración de RSS/Atom Feeds
  feed?: {
    enabled: boolean;
    urls: string[];
  };

  // Configuración de URL Patterns
  pattern?: {
    enabled: boolean;
    // Template de URL con placeholders
    // Ej: "/eventos/{year}/{month}"
    template: string;
    // Parámetros para generar URLs
    params: {
      // Meses hacia adelante para generar
      months_ahead?: number;
      // Meses hacia atrás para generar
      months_back?: number;
      // Valores específicos
      values?: Record<string, string[]>;
    };
  };

  // Rate limiting específico para discovery
  politeness?: {
    max_requests_per_minute: number;
    delay_between_requests_ms: number;
  };
}
```

### Ejemplos de Configuración

#### Sitio con Sitemap Completo
```json
{
  "primary_strategy": "sitemap",
  "fallback_enabled": true,
  "sitemap": {
    "enabled": true,
    "urls": null,
    "content_type_filter": ["events"]
  },
  "crawl": {
    "enabled": true,
    "seed_urls": ["/agenda"],
    "max_depth": 2,
    "include_globs": ["**/event/**"]
  }
}
```

#### Sitio SIN Sitemap
```json
{
  "primary_strategy": "crawl",
  "fallback_enabled": false,
  "crawl": {
    "enabled": true,
    "seed_urls": ["/", "/eventos", "/agenda", "/actividades"],
    "max_depth": 3,
    "strategy": "same-hostname",
    "include_globs": [
      "**/evento/**",
      "**/event/**",
      "**/actividad/**",
      "**/actividades/**"
    ],
    "exclude_globs": [
      "**/tag/**",
      "**/category/**",
      "**/page/**",
      "**/author/**",
      "**/search**",
      "**/wp-admin/**",
      "**/login**"
    ],
    "max_urls": 5000
  }
}
```

#### Sitio con URLs Predecibles
```json
{
  "primary_strategy": "pattern",
  "fallback_enabled": true,
  "pattern": {
    "enabled": true,
    "template": "/eventos/{year}/{month}",
    "params": {
      "months_ahead": 6,
      "months_back": 1
    }
  },
  "crawl": {
    "enabled": true,
    "seed_urls": [],
    "include_globs": ["**/eventos/{year}/{month}/**"]
  }
}
```

#### Estrategia Híbrida (Máxima Cobertura)
```json
{
  "primary_strategy": "hybrid",
  "fallback_enabled": false,
  "sitemap": {
    "enabled": true,
    "urls": null
  },
  "crawl": {
    "enabled": true,
    "seed_urls": ["/agenda"],
    "max_depth": 2,
    "include_globs": ["**/event/**"]
  },
  "feed": {
    "enabled": true,
    "urls": ["/feed/eventos.rss", "/eventos/feed"]
  }
}
```

---

## Sistema de Deduplicación Rápida

### Problema

Cuando ejecutamos discovery periódicamente (ej: cada día), la mayoría de URLs ya existirán en `pages`. Sin un sistema de deduplicación eficiente:
- El Discovery Worker publicaría miles de URLs ya conocidas
- El Event Processor tendría que filtrarlas contra PostgreSQL
- Genera tráfico innecesario y carga en la BD

### Solución: Redis URL Cache

El Discovery Worker consulta un **caché de URLs en Redis** antes de publicar eventos. Esto **no viola el principio Single Writer** porque:
- Redis es **solo lectura** para el Discovery Worker
- El **Event Processor mantiene el caché** sincronizado con PostgreSQL

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    SISTEMA DE DEDUPLICACIÓN CON REDIS                            │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │                          DISCOVERY WORKER                                 │   │
│  │                                                                           │   │
│  │   URL descubierta ──► SHA256(url) ──► EXISTS en Redis? ──┬── NO ──► Publicar │
│  │                                                          │                │   │
│  │                                                          └── SÍ ──► Descartar│
│  │                                                                           │   │
│  │   Solo consulta Redis (SISMEMBER) - NO escribe                           │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │                          EVENT PROCESSOR                                  │   │
│  │                                                                           │   │
│  │   evt.discovery.urls_found ──► INSERT en pages ──► SADD hash a Redis     │   │
│  │                                                                           │   │
│  │   Mantiene sincronía Redis ↔ PostgreSQL                                  │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌────────────────────────────────────────┐                                     │
│  │              REDIS                      │                                     │
│  │                                         │                                     │
│  │   SET urls:known:{source_id}            │  ◄── Contiene url_hash de todas    │
│  │   ├── "a1b2c3d4..."  (url_hash)        │      las páginas de ese source     │
│  │   ├── "e5f6g7h8..."                     │                                     │
│  │   └── ...                               │                                     │
│  │                                         │                                     │
│  │   TTL: Sin expiración (warm on startup) │                                     │
│  └────────────────────────────────────────┘                                     │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Estructura Redis

```
# SET por source con todos los url_hash conocidos
urls:known:{source_id} = SET<url_hash>

# Ejemplo
urls:known:42 = {
  "a1b2c3d4e5f6...",  # SHA256 de https://example.com/event/1
  "f7g8h9i0j1k2...",  # SHA256 de https://example.com/event/2
  ...
}

# Operaciones:
# - SISMEMBER urls:known:42 "hash" → O(1) para verificar existencia
# - SADD urls:known:42 "hash"      → O(1) para añadir nueva URL
# - SCARD urls:known:42            → Contar URLs conocidas
```

### Cache Warming

Al iniciar el Event Processor o al activar un nuevo source, se carga el caché desde PostgreSQL:

```typescript
async function warmUrlCache(sourceId: number) {
  const hashes = await db
    .select({ hash: pages.url_hash })
    .from(pages)
    .where(eq(pages.source_id, sourceId));

  if (hashes.length > 0) {
    await redis.sadd(
      `urls:known:${sourceId}`,
      ...hashes.map(h => h.hash)
    );
  }

  console.log(`Cache warmed for source ${sourceId}: ${hashes.length} URLs`);
}
```

### Flujo de Discovery con Deduplicación

```typescript
// Discovery Worker
class DiscoveryWorker {
  async processDiscoveredUrl(
    sourceId: number,
    url: string
  ): Promise<boolean> {
    const urlHash = sha256(url);

    // Verificar en Redis (O(1))
    const exists = await this.redis.sismember(
      `urls:known:${sourceId}`,
      urlHash
    );

    if (exists) {
      // URL ya conocida - no publicar evento
      this.metrics.increment('discovery.urls.skipped_duplicate');
      return false;
    }

    // URL nueva - será publicada
    return true;
  }

  async handleDiscoveryBatch(sourceId: number, urls: string[]) {
    const newUrls: DiscoveredUrl[] = [];

    for (const url of urls) {
      if (await this.processDiscoveredUrl(sourceId, url)) {
        newUrls.push({
          url,
          url_hash: sha256(url),
          // ... metadata
        });
      }
    }

    if (newUrls.length > 0) {
      await this.publish('evt.discovery.urls_found', {
        source_id: sourceId,
        urls: newUrls,
        stats: {
          total_discovered: urls.length,
          new_urls: newUrls.length,
          duplicate_urls: urls.length - newUrls.length,
        },
      });
    }
  }
}
```

### Event Processor: Mantener Sincronía

```typescript
// Event Processor
class DiscoveryHandler {
  async handleUrlsFound(event: DiscoveryUrlsFoundEvent) {
    const { source_id, urls } = event.payload;

    await db.transaction(async (tx) => {
      // 1. Insertar en PostgreSQL
      for (const url of urls) {
        await tx.insert(pages).values({
          source_id,
          url: url.url,
          url_hash: url.url_hash,
          status: 'pending',
          discovered_by: url.strategy,
        }).onConflictDoNothing(); // Por si hay race condition
      }

      // 2. Actualizar Redis (después del commit exitoso)
      const hashes = urls.map(u => u.url_hash);
      await this.redis.sadd(`urls:known:${source_id}`, ...hashes);
    });
  }
}
```

### Manejo de Inconsistencias

Si Redis se reinicia o pierde datos:

1. **Detección**: El Event Processor detecta URLs "nuevas" que ya existen en BD
2. **Auto-reparación**: Al encontrar conflicto en INSERT, re-sincroniza el caché
3. **Startup**: Cache warming automático al iniciar servicios

```typescript
// Auto-reparación en caso de conflicto
async function handleInsertConflict(sourceId: number, urlHash: string) {
  // La URL ya existía en BD pero no en Redis
  await redis.sadd(`urls:known:${sourceId}`, urlHash);
  metrics.increment('cache.resync.url_added');
}
```

### Alternativa: Bloom Filter

Para sources muy grandes (millones de URLs), considera un **Bloom Filter**:

```typescript
// Probabilístico pero muy eficiente en memoria
// ~1.2 MB para 1M URLs con 1% false positive rate

import { BloomFilter } from 'bloom-filters';

const filter = new BloomFilter(1000000, 0.01);
filter.add(urlHash);

if (filter.has(urlHash)) {
  // Probablemente existe (verificar en Redis/BD si es crítico)
}
```

### Métricas de Deduplicación

```typescript
// Métricas importantes para monitorear
discovery.urls.total          // Total descubiertas
discovery.urls.new            // Nuevas (pasaron filtro)
discovery.urls.skipped_duplicate  // Duplicadas (filtradas por Redis)
discovery.cache.hits          // Aciertos en caché
discovery.cache.misses        // Fallos en caché
discovery.cache.resync        // Re-sincronizaciones
```

---

## Flujo de Procesamiento

### Flujo Completo: Discovery → Evento Guardado

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           FLUJO DE PROCESAMIENTO                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  1. DISCOVERY                                                                    │
│  ┌──────────────┐    cmd.source.discover      ┌──────────────┐                  │
│  │ Scheduler/   │ ─────────────────────────── │  Discovery   │                  │
│  │ Admin API    │                              │   Worker     │                  │
│  └──────────────┘                              │  (Crawlee)   │                  │
│                                                └──────┬───────┘                  │
│                                                       │                          │
│                        evt.discovery.urls_found       │                          │
│                        (batch: urls[], strategy_used) │                          │
│                                                       ▼                          │
│  2. SCRAPING                                  ┌──────────────┐                   │
│                                               │    Event     │                   │
│                     cmd.scrape.page.requested │  Processor   │                   │
│                    ◄──────────────────────────│ (persiste    │                   │
│                    │                          │  pages en BD)│                   │
│                    ▼                          └──────────────┘                   │
│            ┌──────────────┐                                                      │
│            │   Scraping   │                                                      │
│            │   Worker     │                                                      │
│            │  (Crawlee)   │                                                      │
│            └──────┬───────┘                                                      │
│                   │                                                              │
│                   │ evt.scrape.page.completed|failed                            │
│                   ▼                                                              │
│  3. CLASSIFICATION                                                               │
│            ┌──────────────┐                                                      │
│            │    Event     │    cmd.page.classify                                │
│            │  Processor   │ ─────────────────────►┌──────────────┐              │
│            └──────────────┘                       │Classification│              │
│                                                   │   Worker     │              │
│                                                   └──────┬───────┘              │
│                                                          │                       │
│                     evt.page.classified.event|other      │                       │
│                                    ┌─────────────────────┘                       │
│                                    ▼                                             │
│  4. EXTRACTION              ┌──────────────┐                                     │
│                             │    Event     │   cmd.event.extract                │
│                             │  Processor   │ ───────────────────►┌────────────┐ │
│                             └──────────────┘                     │ Extraction │ │
│                                                                  │   Worker   │ │
│                                                                  └─────┬──────┘ │
│                                                                        │         │
│                        evt.event.extracted|duplicate|failed            │         │
│                                    ┌───────────────────────────────────┘         │
│                                    ▼                                             │
│  5. PERSISTENCE             ┌──────────────┐                                     │
│                             │    Event     │                                     │
│                             │  Processor   │                                     │
│                             │ ──────────── │                                     │
│                             │ ESCRIBE BD   │                                     │
│                             │  - events    │                                     │
│                             │  - venues    │                                     │
│                             │  - organizers│                                     │
│                             └──────┬───────┘                                     │
│                                    │                                             │
│                        evt.event.created|updated                                │
│                                    │                                             │
│                                    ▼                                             │
│                             ┌──────────────┐                                     │
│                             │  PostgreSQL  │                                     │
│                             └──────────────┘                                     │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Estados de una Página

```
pending → processing → scraped → classifying → classified → extracting → processed
                 │                    │                           │
                 ▼                    ▼                           ▼
              failed            classified_other            extraction_failed
                                                                  │
                                                                  ▼
                                                              duplicate
```

---

## Servicios y Componentes

### 1. API Gateway

**Responsabilidad**: Punto de entrada para usuarios y sistemas externos.

```typescript
// Endpoints principales
POST /api/sources                    // Crear nueva fuente
POST /api/sources/:id/discover       // Iniciar discovery
GET  /api/sources/:id/discovery-status // Estado del discovery
GET  /api/events                     // Listar eventos
GET  /api/events/:id                 // Detalle de evento
```

### 2. Discovery Worker (Crawlee)

**Responsabilidad**: Descubrir URLs de eventos usando múltiples estrategias.

**Input**: `cmd.source.discover`
**Output**: `evt.discovery.urls_found`

```typescript
class DiscoveryWorker {
  async handleCommand(cmd: SourceDiscoverCommand) {
    const config = cmd.payload.discovery_config;
    const discoveredUrls: DiscoveredUrl[] = [];

    // Ejecutar estrategia primaria
    const primaryUrls = await this.executeStrategy(
      config.primary_strategy,
      config
    );
    discoveredUrls.push(...primaryUrls);

    // Fallback si está habilitado y no hay resultados
    if (config.fallback_enabled && discoveredUrls.length === 0) {
      const fallbackUrls = await this.executeFallback(config);
      discoveredUrls.push(...fallbackUrls);
    }

    // Publicar evento con URLs descubiertas (NO escribe en BD)
    await this.publishEvent('evt.discovery.urls_found', {
      source_id: cmd.payload.source_id,
      urls: discoveredUrls,
      strategy_used: config.primary_strategy,
      stats: {
        total_discovered: discoveredUrls.length,
        by_strategy: this.groupByStrategy(discoveredUrls),
      },
    });
  }
}
```

### 3. Scraping Worker (Crawlee)

**Responsabilidad**: Obtener HTML de páginas web.

**Input**: `cmd.scrape.page.requested`
**Output**: `evt.scrape.page.completed` | `evt.scrape.page.failed`

```typescript
class ScrapingWorker {
  private httpCrawler: CheerioCrawler;
  private browserCrawler: PlaywrightCrawler;

  async handleCommand(cmd: ScrapePageRequestedCommand) {
    const { requires_javascript } = cmd.payload.scrape_config || {};
    const crawler = requires_javascript ? this.browserCrawler : this.httpCrawler;

    await crawler.addRequests([{
      url: cmd.payload.url,
      userData: {
        pageId: cmd.payload.page_id,
        correlationId: cmd.correlation_id,
        causationId: cmd.message_id,
      },
    }]);
  }
}
```

### 4. Classification Worker

**Responsabilidad**: Determinar si una página contiene un evento.

**Input**: `cmd.page.classify`
**Output**: `evt.page.classified.event` | `evt.page.classified.other`

**Métodos de clasificación**:
- Rule-based (patrones URL, selectores CSS, Schema.org)
- ML model (futuro)
- Híbrido

### 5. Extraction Worker

**Responsabilidad**: Extraer datos estructurados del HTML.

**Input**: `cmd.event.extract`
**Output**: `evt.event.extracted` | `evt.event.duplicate` | `evt.event.extraction_failed`

**Usa**: `technology_templates` + `parsing_rules` + `source_configurations`

### 6. Event Processor

**Responsabilidad**: Orquestar el flujo y persistir en BD.

**ÚNICO SERVICIO QUE ESCRIBE EN BASE DE DATOS**

```typescript
class EventProcessor {
  async handleEvent(event: EnvelopeV1) {
    switch (event.message_type) {
      case 'evt.discovery.urls_found':
        return this.handleDiscoveryCompleted(event);
      case 'evt.scrape.page.completed':
        return this.handleScrapeCompleted(event);
      case 'evt.page.classified.event':
        return this.handleClassifiedAsEvent(event);
      case 'evt.event.extracted':
        return this.handleEventExtracted(event);
    }
  }

  private async handleDiscoveryCompleted(event: EnvelopeV1) {
    const { urls, source_id } = event.payload;

    await db.transaction(async (tx) => {
      // Insertar nuevas páginas en BD
      for (const url of urls) {
        await tx.insert(pages).values({
          source_id,
          url: url.url,
          url_hash: hash(url.url),
          status: 'pending',
          discovered_by: url.strategy,
        }).onConflictDoNothing();
      }
    });

    // Encolar scraping para cada URL nueva
    for (const url of urls) {
      await this.emitCommand('cmd.scrape.page.requested', { ... });
    }
  }
}
```

---

## Estructura de Directorios

```
eventhound/
├── docs/                           # Documentación
│   ├── ARCHITECTURE.md             # Este documento
│   ├── MIGRATIONS.md               # Documentación de migraciones
│   └── CONTRACTS.md                # Especificación de contratos
│
├── packages/                       # Monorepo con paquetes compartidos
│   └── shared/                     # Tipos y utilidades compartidas
│       ├── src/
│       │   ├── types/              # Tipos TypeScript compartidos
│       │   └── utils/              # Utilidades comunes
│       └── package.json
│
├── services/                       # Microservicios
│   ├── api-gateway/                # API REST/GraphQL
│   │   ├── src/
│   │   │   ├── routes/
│   │   │   ├── controllers/
│   │   │   └── middleware/
│   │   ├── Dockerfile
│   │   └── package.json
│   │
│   ├── discovery-worker/           # Worker de discovery (Crawlee)
│   │   ├── src/
│   │   │   ├── strategies/         # Estrategias de discovery
│   │   │   │   ├── sitemap.strategy.ts
│   │   │   │   ├── crawl.strategy.ts
│   │   │   │   ├── feed.strategy.ts
│   │   │   │   └── pattern.strategy.ts
│   │   │   ├── handlers/
│   │   │   └── index.ts
│   │   ├── Dockerfile
│   │   └── package.json
│   │
│   ├── scraping-worker/            # Worker de scraping (Crawlee)
│   │   ├── src/
│   │   │   ├── crawlers/           # Configuraciones Crawlee
│   │   │   │   ├── cheerio.crawler.ts
│   │   │   │   └── playwright.crawler.ts
│   │   │   ├── handlers/
│   │   │   └── index.ts
│   │   ├── Dockerfile
│   │   └── package.json
│   │
│   ├── classification-worker/      # Worker de clasificación
│   │   ├── src/
│   │   │   ├── classifiers/
│   │   │   │   ├── rule-based.ts
│   │   │   │   ├── schema-org.ts
│   │   │   │   └── ml-model.ts
│   │   │   └── handlers/
│   │   ├── Dockerfile
│   │   └── package.json
│   │
│   ├── extraction-worker/          # Worker de extracción
│   │   ├── src/
│   │   │   ├── extractors/
│   │   │   ├── parsers/
│   │   │   └── handlers/
│   │   ├── Dockerfile
│   │   └── package.json
│   │
│   └── event-processor/            # Procesador central (escribe BD)
│       ├── src/
│       │   ├── handlers/
│       │   │   ├── discovery.handler.ts
│       │   │   ├── scrape.handler.ts
│       │   │   ├── classify.handler.ts
│       │   │   ├── extract.handler.ts
│       │   │   └── event.handler.ts
│       │   ├── repositories/
│       │   └── orchestrator.ts
│       ├── Dockerfile
│       └── package.json
│
├── migrations/                     # Migraciones SQL
│   └── webscraping/
│       ├── 001_create_schema_and_basic_tables.sql
│       ├── 002_create_content_tables.sql
│       ├── 003_create_translation_tables.sql
│       ├── 004_create_parsing_rules.sql
│       ├── 005_populate_initial_data.sql
│       ├── 006_add_processing_tracking.sql
│       ├── 007_add_classification_fields.sql
│       └── 008_add_discovery_tracking.sql
│
├── docker/
│   ├── docker-compose.yml
│   ├── docker-compose.dev.yml
│   └── docker-compose.prod.yml
│
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── deploy.yml
│
├── package.json
├── tsconfig.json
└── README.md
```

---

## Integración con Crawlee

### Principios de Integración

1. **Crawlee es un detalle de implementación** de los Workers (Discovery + Scraping)
2. **No se expone en los contratos** de mensajería
3. **Usa storage en memoria** (no PostgreSQL)
4. **Solo publica eventos**, no persiste datos

### Discovery Worker con Crawlee

```typescript
// services/discovery-worker/src/strategies/crawl.strategy.ts
import { PlaywrightCrawler, EnqueueLinksOptions } from 'crawlee';

export class CrawlStrategy implements DiscoveryStrategy {
  async execute(
    source: Source,
    config: CrawlConfig
  ): Promise<DiscoveredUrl[]> {
    const discoveredUrls: DiscoveredUrl[] = [];

    const crawler = new PlaywrightCrawler({
      maxRequestsPerCrawl: config.max_urls || 1000,
      maxConcurrency: 5,

      async requestHandler({ page, request, enqueueLinks }) {
        // Registrar URL descubierta
        discoveredUrls.push({
          url: request.url,
          strategy: 'crawl',
          depth: request.userData.depth || 0,
        });

        // Seguir enlaces según configuración
        if ((request.userData.depth || 0) < config.max_depth) {
          await enqueueLinks({
            strategy: config.strategy, // 'same-hostname'
            globs: config.include_globs,
            exclude: config.exclude_globs,
            transformRequestFunction: (req) => {
              req.userData.depth = (request.userData.depth || 0) + 1;
              return req;
            },
          });
        }
      },
    });

    // Iniciar desde seed URLs
    await crawler.addRequests(
      config.seed_urls.map(path => ({
        url: new URL(path, source.base_url).href,
        userData: { depth: 0 },
      }))
    );

    await crawler.run();

    return discoveredUrls;
  }
}
```

### Sitemap Strategy con Crawlee

```typescript
// services/discovery-worker/src/strategies/sitemap.strategy.ts
import { Sitemap, RobotsFile } from 'crawlee';

export class SitemapStrategy implements DiscoveryStrategy {
  async execute(
    source: Source,
    config: SitemapConfig
  ): Promise<DiscoveredUrl[]> {
    const discoveredUrls: DiscoveredUrl[] = [];

    try {
      // Obtener URLs de sitemap desde robots.txt o config
      let sitemapUrls: string[] = config.urls || [];

      if (!sitemapUrls.length) {
        const robots = await RobotsFile.find(source.base_url);
        sitemapUrls = robots.getSitemapUrls();
      }

      // Procesar cada sitemap
      for (const sitemapUrl of sitemapUrls) {
        const sitemap = await Sitemap.load(sitemapUrl);

        for (const url of sitemap.urls) {
          // Aplicar filtros si están configurados
          if (this.matchesFilter(url, config.content_type_filter)) {
            discoveredUrls.push({
              url,
              strategy: 'sitemap',
              sitemap_url: sitemapUrl,
            });
          }
        }
      }
    } catch (error) {
      // Sitemap no disponible - no es un error fatal
      console.log(`Sitemap not available for ${source.base_url}`);
    }

    return discoveredUrls;
  }
}
```

### Scraping Worker con Crawlee

```typescript
// services/scraping-worker/src/index.ts
import { CheerioCrawler, PlaywrightCrawler, Configuration } from 'crawlee';

// NO persistir en disco
Configuration.set('persistStorage', false);

class ScrapingWorker {
  private httpCrawler: CheerioCrawler;
  private browserCrawler: PlaywrightCrawler;

  constructor(private messageQueue: MessageBroker) {
    this.initializeCrawlers();
  }

  private initializeCrawlers() {
    const commonConfig = {
      requestHandler: this.handleRequest.bind(this),
      failedRequestHandler: this.handleFailedRequest.bind(this),
    };

    this.httpCrawler = new CheerioCrawler({
      ...commonConfig,
      maxRequestsPerMinute: 120,
      maxConcurrency: 10,
    });

    this.browserCrawler = new PlaywrightCrawler({
      ...commonConfig,
      maxRequestsPerMinute: 30,
      maxConcurrency: 5,
      launchContext: {
        launchOptions: { headless: true },
      },
    });
  }

  private async handleRequest({ request, $, page, response }) {
    const html = $ ? $.html() : await page?.content();
    const startTime = request.userData.startTime || Date.now();

    // PUBLICAR EVENTO (no escribir en BD)
    await this.messageQueue.publish('scrape.events', {
      message_id: uuidv4(),
      message_type: 'evt.scrape.page.completed',
      correlation_id: request.userData.correlationId,
      causation_id: request.userData.causationId,
      tenant_id: request.userData.tenantId,
      aggregate: { type: 'page', id: request.userData.pageId },
      payload: {
        page_id: request.userData.pageId,
        url: request.url,
        tenant_id: request.userData.tenantId,
        result: {
          html,
          status_code: response?.status() || 200,
          headers: Object.fromEntries(response?.headers() || []),
          metadata: {
            response_time_ms: Date.now() - startTime,
            crawler_type: $ ? 'cheerio' : 'playwright',
            content_length: html.length,
          },
        },
      },
    });
  }

  private async handleFailedRequest({ request, error }) {
    await this.messageQueue.publish('scrape.events', {
      message_id: uuidv4(),
      message_type: 'evt.scrape.page.failed',
      correlation_id: request.userData.correlationId,
      causation_id: request.userData.causationId,
      tenant_id: request.userData.tenantId,
      aggregate: { type: 'page', id: request.userData.pageId },
      payload: {
        page_id: request.userData.pageId,
        url: request.url,
        tenant_id: request.userData.tenantId,
        error: {
          code: 'SCRAPE_FAILED',
          message: error.message,
          details: { retries: request.retryCount },
        },
      },
    });
  }
}
```

---

## Integración con urbanmoop-contracts

### Instalación

```bash
# Configurar .npmrc para GitHub Packages
echo "@urbanmoop:registry=https://npm.pkg.github.com" >> .npmrc
echo "//npm.pkg.github.com/:_authToken=\${GITHUB_TOKEN}" >> .npmrc

# Instalar el paquete
npm install @urbanmoop/contracts
```

### Uso en Servicios

```typescript
import {
  // Tipos
  type EnvelopeV1,

  // Constantes
  MESSAGE_TYPES,

  // Registry y validación
  MessageRegistry,
  validateMessage,

  // Builders
  buildSourceDiscoverCommand,
  buildDiscoveryUrlsFoundEvent,
  buildScrapePageCompletedEvent,
  buildPageClassifyCommand,
  buildEventExtractCommand,

  // Errores
  EnvelopeValidationError,
  PayloadValidationError,
} from '@urbanmoop/contracts';

// Crear registry con todos los schemas
const registry = new MessageRegistry();

// Validar mensaje entrante
async function processMessage(rawMessage: unknown) {
  const message = validateMessage(rawMessage, registry);

  switch (message.message_type) {
    case MESSAGE_TYPES.CMD_SOURCE_DISCOVER:
      return handleDiscoverCommand(message);
    case MESSAGE_TYPES.EVT_DISCOVERY_URLS_FOUND:
      return handleUrlsFound(message);
    // ... otros handlers
  }
}
```

---

## Sistema de Configuración por Capas

### Jerarquía de Configuración

```
┌─────────────────────────────────────────────────────────────────┐
│                    JERARQUÍA DE CONFIGURACIÓN                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Capa 1: TECHNOLOGY TEMPLATE (Base)                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  technology_templates                                    │   │
│  │  ├─ WordPress + Yoast SEO                               │   │
│  │  ├─ WordPress + Events Calendar                         │   │
│  │  ├─ Drupal                                              │   │
│  │  └─ Custom HTML                                         │   │
│  │                                                          │   │
│  │  Contiene:                                               │   │
│  │  - discovery_config (patrones sitemap, estrategia)       │   │
│  │  - parsing_config (selectores base)                      │   │
│  │  - normalization_config (transformaciones)               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼ hereda + override                 │
│  Capa 2: SOURCE CONFIGURATION (Por sitio)                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  source_configurations                                   │   │
│  │                                                          │   │
│  │  Contiene:                                               │   │
│  │  - discovery_config (overrides: seed_urls, globs)        │   │
│  │  - overrides_config (selectores específicos)             │   │
│  │  - politeness_config (rate limiting)                     │   │
│  │  - recrawl_config (intervalos)                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼ reglas específicas                │
│  Capa 3: PARSING RULES (Reglas de extracción)                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  parsing_rules                                           │   │
│  │                                                          │   │
│  │  - Reglas de template (is_template_rule = true)          │   │
│  │  - Reglas específicas por source                         │   │
│  │  - Prioridad y orden de aplicación                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Base de Datos

### Schema Principal: `webscraping`

Ver documento [MIGRATIONS.md](./MIGRATIONS.md) para detalle completo.

**Tablas principales:**

| Tabla | Propósito |
|-------|-----------|
| `sources` | Fuentes de datos (sitios web) |
| `source_info` | Info dinámica de robots.txt |
| `source_configurations` | Configuración específica por sitio (incluye discovery_config) |
| `technology_templates` | Templates por CMS/tecnología |
| `pages` | URLs descubiertas y su estado |
| `page_processing_history` | Historial de procesamiento |
| `discovery_runs` | Ejecuciones de discovery |
| `discovered_urls` | URLs descubiertas por run |
| `discovery_schedules` | Programación de discovery automático |
| `discovery_stats` (VIEW) | Vista de estadísticas de discovery |
| `events` | Eventos extraídos |
| `event_translations` | Traducciones de eventos |
| `venues` | Lugares de eventos |
| `organizers` | Organizadores |
| `parsing_rules` | Reglas de extracción |
| `classification_rules` | Reglas de clasificación |

---

## Configuración de Entorno

### Variables de Entorno

```bash
# Base de datos
DATABASE_URL=postgresql://user:pass@localhost:5432/eventhound
DATABASE_SCHEMA=webscraping

# Message Broker
RABBITMQ_URL=amqp://user:pass@localhost:5672
RABBITMQ_EXCHANGE=eventhound

# Redis
REDIS_URL=redis://localhost:6379

# Crawlee (para workers)
CRAWLEE_STORAGE_DIR=/tmp/crawlee
CRAWLEE_PERSIST_STORAGE=false

# Discovery Worker
DISCOVERY_WORKER_MAX_URLS_PER_RUN=5000
DISCOVERY_WORKER_DEFAULT_STRATEGY=hybrid

# Scraping Worker
SCRAPING_WORKER_CONCURRENCY=10
SCRAPING_WORKER_MAX_RPM=120

# Logging
LOG_LEVEL=info
LOG_FORMAT=json
```

### Docker Compose (Desarrollo)

```yaml
version: '3.8'
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: eventhound
      POSTGRES_USER: eventhound
      POSTGRES_PASSWORD: secret
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  rabbitmq:
    image: rabbitmq:3.12-management
    ports:
      - "5672:5672"
      - "15672:15672"

  redis:
    image: redis:7
    ports:
      - "6379:6379"

  discovery-worker:
    build: ./services/discovery-worker
    environment:
      RABBITMQ_URL: amqp://rabbitmq:5672
      CRAWLEE_PERSIST_STORAGE: "false"
    depends_on:
      - rabbitmq

  scraping-worker:
    build: ./services/scraping-worker
    environment:
      RABBITMQ_URL: amqp://rabbitmq:5672
      CRAWLEE_PERSIST_STORAGE: "false"
    depends_on:
      - rabbitmq

  classification-worker:
    build: ./services/classification-worker
    environment:
      RABBITMQ_URL: amqp://rabbitmq:5672
    depends_on:
      - rabbitmq

  extraction-worker:
    build: ./services/extraction-worker
    environment:
      RABBITMQ_URL: amqp://rabbitmq:5672
    depends_on:
      - rabbitmq

  event-processor:
    build: ./services/event-processor
    environment:
      DATABASE_URL: postgresql://eventhound:secret@postgres:5432/eventhound
      RABBITMQ_URL: amqp://rabbitmq:5672
    depends_on:
      - postgres
      - rabbitmq

  api-gateway:
    build: ./services/api-gateway
    environment:
      DATABASE_URL: postgresql://eventhound:secret@postgres:5432/eventhound
      RABBITMQ_URL: amqp://rabbitmq:5672
    ports:
      - "3000:3000"
    depends_on:
      - postgres
      - rabbitmq

volumes:
  postgres_data:
```

---

## GitHub Copilot SDK

### Integración en el Proyecto

El proyecto `urbanmoop-contracts` incluye integración con GitHub Copilot SDK para desarrollo asistido.

### Casos de Uso

1. **Generación de Schemas Zod**
2. **Creación de Tests Automáticos**
3. **Documentación de Contratos**

Ver documentación completa en `urbanmoop-contracts/docs/copilot-sdk.md`.

---

## Referencias

- [urbanmoop-contracts README](https://github.com/cruizmol/urbanmoop-contracts)
- [Crawlee Documentation](https://crawlee.dev/)
- [Crawlee enqueueLinks API](https://crawlee.dev/js/api/core/function/enqueueLinks)
- [Documentación de Migraciones](./MIGRATIONS.md)
- [Especificación de Contratos](./CONTRACTS.md)
