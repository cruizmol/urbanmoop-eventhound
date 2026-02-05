# 📐 Convenciones del Proyecto

Este documento registra las convenciones y acuerdos establecidos para el desarrollo de `eventhound`.

## 🌿 Git & Branching

### Nombres de ramas

- **Formato (features/bugs):** `feature/issue-N-descripción-corta`
- **Ejemplo:** `feature/issue-4-docker-compose-setup`
- **Regla:** Para desarrollo (features/bugs), **siempre** incluir número de issue
- **Excepción (sin issue asociado):**
  - Documentación: `docs/descripción-corta` (ej: `docs/add-project-conventions`)
  - Tareas administrativas: `chore/descripción-corta` (ej: `chore/update-ci-config`)

### Pull Requests

- **Título:** Mismo nombre que la rama
- **Convención establecida:** PR title = branch name
- **Template:** Usar `.github/PULL_REQUEST_TEMPLATE.md` (siempre)
- **Cierre automático:** Usar `Closes #N` en la descripción del PR

### Merge Strategy

- **Features/Issues:** `Merge commit` (preservar historial completo)
  - Mantiene trazabilidad del proceso de desarrollo
  - Fácil de revertir (un solo commit de merge)
  - Contexto completo de iteraciones y fixes
- **Hotfixes/Typos:** `Squash and merge` (historial limpio)
  - Para cambios triviales de 1-2 commits
  - Mantiene el historial lineal y legible
- **Nunca:** `Rebase and merge` (para evitar conflictos y pérdida de contexto)

### Workflow

- ✅ **Siempre:** Crear PR antes de merge a main
- ❌ **Nunca:** Push directo a main
- **Regla:** PR workflow obligatorio (establecido 2026-02-05)

## 📁 Documentación

### Estructura de archivos

- **README.md:** Solo en la raíz del proyecto
- **Otros docs:** Siempre en `docs/` o subdirectorios con su propio README
- **Ejemplos:** `examples/README.md` para guías de ejemplos

### Documentación principal

- `docs/ARCHITECTURE.md` - Arquitectura event-driven y Single Writer principle
- `docs/CONTRACTS.md` - Especificación de contratos de mensajería
- `docs/MIGRATIONS.md` - Documentación de migraciones SQL
- `docs/PLAN.md` - Plan de desarrollo completo (5 fases, 11-13 semanas)
- `docs/CONVENTIONS.md` - Este documento

## 📦 Package & Dependencies

### Monorepo Workspace

- Estructura: `packages/*` y `services/*`
- Root package.json con workspaces configurados
- Cada servicio y paquete tiene su propio package.json

### ES Modules

- `"type": "module"` en package.json (si aplica por servicio)
- Preferir import/export sobre require

### Scripts

- Scripts que no están configurados deben **fallar explícitamente** con exit code 1
- Scripts root disponibles:
  - `npm run dev:infra` - Levantar Docker Compose
  - `npm run lint` - ESLint
  - `npm run format` - Prettier
  - `npm run typecheck` - TypeScript
  - `npm test` - Jest (unit + integration + e2e)

### Dependencies

- **dependencies:** Solo lo necesario en runtime
- **devDependencies:** Herramientas de desarrollo, testing
- **@urbanmoop/contracts:** Usar como dependencia en todos los servicios

## 🎨 Estilo de Código

### Prettier

Principales settings recomendados (a configurar en `.prettierrc`):

- Single quotes (`'`)
- Trailing commas (`all`)
- Semi: `true`
- Print width: 100
- Tab width: 2
- Arrow parens: `always`
- End of line: `lf`

### ESLint

- TypeScript strict rules
- `@typescript-eslint/no-unused-vars` con prefix `_` para ignorar
- `@typescript-eslint/no-explicit-any` como warning (no error)
- `no-console` permitido (scripts/logs)

### Naming Conventions

- **Variables/Functions:** `camelCase`
- **Classes:** `PascalCase`
- **Constants:** `UPPER_SNAKE_CASE`
- **Files:** `kebab-case.ts`
- **Message types:** `cmd.aggregate.action` o `evt.aggregate.past_participle`

## 🏗️ Event-Driven Architecture Conventions

### Single Writer Principle ⚠️ CRITICAL

- **SOLO el Event Processor puede escribir en la base de datos**
- Workers (Discovery, Scraping, Classification, Extraction):
  - ✅ Leer configuración de BD (si es necesario)
  - ✅ Publicar eventos a RabbitMQ
  - ❌ **NUNCA** escribir directamente a PostgreSQL

### Message Contracts

- **Siempre** usar `@urbanmoop/contracts` para:
  - Tipos de mensajes (`EnvelopeV1`, payloads)
  - Builders (`buildSourceDiscoverCommand`, etc.)
  - Validación (`validateMessage`)
- **Nunca** crear schemas de mensajes manualmente
- **Contratos agnósticos:** No exponer detalles de implementación (Crawlee, etc.)

### Event Flow

```
API Gateway → Command → Worker → Event → Event Processor → Database
```

- Mantener correlation_id y causation_id en toda la cadena
- Logs estructurados con correlation_id obligatorio

### Error Handling

- Publicar eventos de error en lugar de fallar silenciosamente
- Usar structured logging con contexto completo
- No reintentar indefinidamente (usar dead letter queues)

## 🧪 Testing

### Jest

- Tests en `__tests__/` dentro de cada servicio/paquete
- Naming: `nombre-modulo.test.ts`
- Cobertura de funciones públicas exportadas
- Estructura AAA (Arrange, Act, Assert)

### Test Structure

```typescript
describe('DiscoveryHandler', () => {
  describe('handleUrlsFound', () => {
    it('should publish scrape commands for discovered URLs', async () => {
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

### Test Ratio Guidelines

| Tipo de Código                | Ratio Tests:Code | Ejemplo                                 |
| ----------------------------- | ---------------- | --------------------------------------- |
| Handlers de mensajes          | 2:1 a 3:1        | Event handlers con validación completa  |
| Servicios de negocio          | 2:1 a 3:1        | Discovery, Classification, Extraction   |
| Repositories (Event Processor)| 2:1              | DB operations con transaction tests     |
| Utilidades puras              | 2:1              | Pure functions sin side effects         |
| Strategies                    | 3:1              | Strategy pattern con múltiples casos    |

**Red flags:**

- Ratio > 5:1 → Probablemente over-testing
- Tests > 400 líneas para < 150 líneas código → Reducir tests redundantes
- Más tiempo escribiendo tests que código → Revisar strategy

## 🚀 CI/CD

### GitHub Actions (planificado para M8)

- Workflow principal: `.github/workflows/ci.yml` (a crear)
- Ejecutará en: `push` a main + `pull_request` a main
- Pipeline planificado:
  1. `npm ci` (instalar dependencias)
  2. `npm run lint` (ESLint)
  3. `npm run typecheck` (TypeScript)
  4. `npm test` (Jest)
  5. `npm run build` (compilar servicios)

### Branch Protection (futuro)

- Require PR reviews
- Require status checks to pass
- Require branches to be up to date

## 💬 Idioma

### Código

- Variables, funciones, tipos: **Inglés**
- Comentarios: **Español** (preferible) o inglés

### Documentación

- README principal: **Español**
- Docs: **Español**
- Ejemplos: Comentarios en **español**

### PRs y Issues

- Títulos y descripciones: **Español**
- Mensajes de commit: **Inglés** (formato convencional)
- **Commits con asistencia de IA:** Incluir `Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>` al final del mensaje

## 📋 Issues & Milestones

### Labels establecidos

#### Area (componente del sistema)
- `area:api-gateway` - REST API para usuarios
- `area:discovery-worker` - Worker de descubrimiento de URLs
- `area:scraping-worker` - Worker de scraping HTML
- `area:classification-worker` - Worker de clasificación de páginas
- `area:extraction-worker` - Worker de extracción de datos
- `area:event-processor` - Procesador de eventos (single writer)
- `area:shared` - Paquetes compartidos
- `area:database` - Migraciones SQL y schema
- `area:messaging` - RabbitMQ, contratos de mensajería
- `area:infrastructure` - Docker, CI/CD, deployment

#### Priority
- `prio:P0` - Bloqueante / critical path
- `prio:P1` - Importante, no bloqueante
- `prio:P2` - Nice-to-have / posterior

#### Type
- `type:feature` - Nueva funcionalidad
- `type:bug` - Corrección de error
- `type:chore` - Tooling, CI, refactors, mantenimiento
- `type:docs` - Documentación
- `type:test` - Tests unit/integration/e2e

#### Operations
- `ops:breaking-change` - Cambios breaking
- `ops:governance` - PR template, CODEOWNERS, políticas
- `ops:security` - Vulnerabilidades, seguridad

### Milestones

**Nota:** Los Milestones M0-M9 son la implementación granular en GitHub Issues. Se agrupan en 5 FASES de alto nivel documentadas en `docs/PLAN.md`:

- **FASE 1** (2-3 semanas): M0 + contratos (@urbanmoop/contracts)
- **FASE 2** (2 semanas): M1 + M2
- **FASE 3** (3 semanas): M3 + M4
- **FASE 4** (2 semanas): M5 + M6
- **FASE 5** (2-3 semanas): M7 + M8 + M9

#### Milestones de implementación:

- **M0 — Database & Infrastructure** - Setup base: PostgreSQL, RabbitMQ, Redis, migrations, monorepo
- **M1 — Shared Packages** - Código compartido: tipos, utilities, messaging, database
- **M2 — Event Processor** - Single writer: handlers, repositories, orchestration
- **M3 — Discovery Worker** - Descubrimiento de URLs: sitemap, crawling, RSS, patterns
- **M4 — Scraping Worker** - Obtención de HTML: Crawlee HTTP + Browser
- **M5 — Classification Worker** - Clasificación de páginas: rule-based, ML
- **M6 — Extraction Worker** - Extracción de datos: schemas, normalization
- **M7 — API Gateway** - REST API: endpoints, authentication, rate limiting
- **M8 — Testing & CI/CD** - Tests completos, CI/CD pipelines, monitoring
- **M9 — Production Deployment** - Deploy a producción, observability, alerting

## 🔍 Development Workflow (Pre-Implementation Analysis)

**Propósito:** Prevenir scope creep, over-engineering y breaking changes innecesarios mediante análisis sistemático antes de implementar.

### Pre-Implementation Checklist (~25 min)

Ejecutar ANTES de escribir cualquier código para un issue/feature:

#### 1. Scope Validation (5 min)

- [ ] Leer los requerimientos del issue DOS veces
- [ ] Listar EXACTAMENTE qué debe crearse/modificarse
- [ ] Identificar cualquier cosa NO mencionada en el issue (fuera de scope)
- [ ] Estimar: líneas de código, tests, archivos afectados
- [ ] **Red flag:** Si estimas >500 líneas, considerar dividir en sub-issues

#### 2. Existing Code Analysis (10 min)

- [ ] Encontrar módulos similares en el proyecto (grep por patterns)
- [ ] Comparar patterns existentes (naming, estructura, exports)
- [ ] Revisar patterns de tests (describe/it estructura, assertions típicas)
- [ ] Notar convenciones de naming (camelCase, snake_case, etc.)
- [ ] Verificar patterns de manejo de errores existentes
- [ ] **Red flag:** Si tu approach difiere del código existente, justificar

#### 3. Architecture Validation (5 min)

- [ ] Verificar que respeta Single Writer Principle
- [ ] Verificar que los contratos son agnósticos de implementación
- [ ] Confirmar que workers no escriben a BD
- [ ] Validar que se usan builders de `@urbanmoop/contracts`
- [ ] Verificar correlation_id/causation_id chain
- [ ] **Red flag:** Worker escribiendo a BD = violación crítica

#### 4. Test Strategy (5 min)

- [ ] Contar tests existentes en módulos similares
- [ ] Calcular ratio esperado (target: 2:1 a 3:1)
- [ ] Listar escenarios de test (happy path, errores, edge cases)
- [ ] Eliminar tests nice-to-have (serialización, instanceof chains repetitivos)
- [ ] **Red flag:** Si tests > 400 líneas para <150 líneas de código, reducir scope

#### 5. Implementation Plan (2 min)

- [ ] Confirmar que solo implementas lo que está en scope
- [ ] Definir orden de implementación (código + tests incrementales)
- [ ] Planear validación: `npm run lint && npm test` después de cada unidad lógica
- [ ] Criterio de parada: cuando se cumplan los requerimientos (no gold-plating)

### Anti-Patterns a Evitar

❌ **Violación de Single Writer:**

```typescript
// Worker escribiendo a DB
// ❌ MAL: Discovery Worker insertando páginas directamente
await db.insert(pages).values({ url, source_id });

// ✅ BIEN: Publicar evento para que Event Processor lo maneje
await broker.publish('discovery.events', buildDiscoveryUrlsFoundEvent({ urls }));
```

❌ **Contratos No Agnósticos:**

```typescript
// ❌ MAL: Exponiendo detalles de Crawlee en contratos
interface ScrapeCommand {
  crawlee_request_id: string; // Implementation detail!
}

// ✅ BIEN: Contrato agnóstico
interface ScrapeCommand {
  url: string;
  requires_javascript: boolean;
}
```

❌ **Scope Creep:**

```typescript
// Issue: "Implementar Discovery Worker con estrategia sitemap"
// ❌ MAL: También implementar RSS, crawling, patterns (no pedido)
// ✅ BIEN: Solo implementar estrategia sitemap
```

❌ **Over-Testing:**

```typescript
// ❌ MAL: 6 tests para verificar que un handler funciona
it('should store correlation_id', () => { ... });
it('should store message_id', () => { ... });
it('should update timestamp', () => { ... });

// ✅ BIEN: 1-2 tests de comportamiento, enfoque en lógica de negocio
it('should process URLs and publish scrape commands', () => { ... });
```

### Example: Good Implementation Flow

```markdown
Issue #15: "Implementar handler para evt.scrape.page.completed"

✅ Pre-Implementation (25 min):

1. Scope: Handler function + actualizar página + publicar cmd.page.classify
2. Similar code: Revisar otros handlers en event-processor
3. Architecture: Event Processor escribe a BD ✅, usa correlation chain ✅
4. Tests: Estimar ~120 líneas (ratio 2:1 para ~60 líneas código)
5. Plan: Handler → DB update → Event publish → Tests

✅ Implementation:

- Commit 1: Handler function (~60 líneas código, ~80 tests happy path)
- Commit 2: Error handling (~20 líneas código, ~40 tests error cases)
- Commit 3: Integration tests (~30 tests end-to-end)

Total: ~80 líneas código, ~150 líneas tests (ratio 1.9:1) ✅
```

## 🔐 Security

### Environment Variables

```typescript
// ✅ Validar environment variables
const config = {
  database: {
    url: process.env.DATABASE_URL || throwError('DATABASE_URL required'),
  },
};

// ❌ No hardcodear secrets
const password = 'mysecret123'; // No!
```

### SQL Injection

```typescript
// ✅ Usar Drizzle ORM (protección automática)
await db.select().from(pages).where(eq(pages.id, pageId));

// ❌ No construir SQL manualmente
await db.execute(`SELECT * FROM pages WHERE id = ${pageId}`); // No!
```

### Input Validation

- Usar Zod schemas para validar input
- Sanitizar URLs antes de scraping
- Validar message envelopes con `validateMessage`

## 🔄 Historial de cambios importantes

| Fecha      | PR/Issue | Decisión                                                  |
| ---------- | -------- | --------------------------------------------------------- |
| 2026-02-05 | -        | Establecido PR workflow obligatorio (no push directo a main) |
| 2026-02-05 | -        | Template de PR y Copilot instructions creados             |
| 2026-02-05 | -        | CONVENTIONS.md establecido                                |

---

**Última actualización:** 2026-02-05
**Mantenido por:** @cruizmol
