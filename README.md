# Eventhound

[![CI](https://github.com/cruizmol/urbanmoop-eventhound/workflows/CI/badge.svg)](https://github.com/cruizmol/urbanmoop-eventhound/actions)

**Eventhound** es una plataforma de agregación de eventos culturales que utiliza web scraping inteligente para descubrir, clasificar, extraer y normalizar información de eventos desde múltiples fuentes web.

## 🏗️ Arquitectura

Sistema event-driven basado en microservicios:

- **API Gateway** - REST API para usuarios
- **Discovery Worker** - Descubre URLs (sitemap, crawling, RSS, patterns)
- **Scraping Worker** - Obtiene HTML (Crawlee HTTP/Browser)
- **Classification Worker** - Clasifica páginas (evento vs no-evento)
- **Extraction Worker** - Extrae datos estructurados
- **Event Processor** - Orquesta flujo y escribe en BD (single writer)

## 🚀 Stack Tecnológico

- **Runtime:** Node.js 20+ con TypeScript 5
- **Base de Datos:** PostgreSQL 15+ (schema: `webscraping`)
- **Message Broker:** RabbitMQ 3.12+ (comunicación asíncrona)
- **Cache:** Redis 7 (deduplicación de URLs)
- **Scraping Engine:** Crawlee (HTTP + Browser)
- **ORM:** Drizzle ORM
- **Validación:** Zod (runtime schemas)

## 📂 Estructura del Proyecto

```
eventhound/
├── docs/                    # Documentación completa
│   ├── ARCHITECTURE.md      # Arquitectura event-driven
│   ├── CONTRACTS.md         # Contratos de mensajería
│   ├── MIGRATIONS.md        # Documentación de migraciones
│   └── PLAN.md              # Plan de desarrollo
├── migrations/              # Migraciones SQL
├── packages/                # Monorepo packages
│   └── shared/             # Código compartido
├── services/                # Microservicios
│   ├── api-gateway/
│   ├── discovery-worker/
│   ├── scraping-worker/
│   ├── classification-worker/
│   ├── extraction-worker/
│   └── event-processor/
└── docker/                  # Docker Compose configs
```

## 🎯 Estado del Proyecto

**Fase Actual:** Fase 1 - Contratos y Base de Datos

### ✅ Completado
- Documentación completa (ARCHITECTURE.md, MIGRATIONS.md, CONTRACTS.md, PLAN.md)
- Migraciones SQL base (001-005 de 8)
- 67 issues creados en GitHub con 9 milestones

### 🚧 En Progreso
- Migraciones SQL 006-008
- Setup de infraestructura (Docker Compose)
- Configuración de monorepo

## 📋 Desarrollo

### Requisitos Previos

- Node.js 20+ y npm
- Docker y Docker Compose
- PostgreSQL 15+
- RabbitMQ 3.12+
- Redis 7+

### Instalación

```bash
# Clonar repositorio
git clone https://github.com/cruizmol/urbanmoop-eventhound.git
cd urbanmoop-eventhound

# Instalar dependencias (cuando el monorepo esté configurado)
npm install

# Levantar infraestructura de desarrollo
npm run dev:infra
```

### Migraciones de Base de Datos

```bash
# Configurar DATABASE_URL
export DATABASE_URL="postgresql://eventhound:secret@localhost:5432/eventhound"

# Ejecutar migraciones
psql $DATABASE_URL -f migrations/001_create_schema_and_basic_tables.sql
psql $DATABASE_URL -f migrations/002_create_content_tables.sql
psql $DATABASE_URL -f migrations/003_create_translation_tables.sql
psql $DATABASE_URL -f migrations/004_create_parsing_rules.sql
psql $DATABASE_URL -f migrations/005_populate_initial_data.sql
# ... (006-008 pendientes)
```

## 📖 Documentación

- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Arquitectura completa del sistema
- **[CONTRACTS.md](docs/CONTRACTS.md)** - Especificación de contratos de mensajería
- **[MIGRATIONS.md](docs/MIGRATIONS.md)** - Documentación de migraciones SQL
- **[PLAN.md](docs/PLAN.md)** - Plan de desarrollo completo (5 fases, 11-13 semanas)

## 🤝 Contribuir

El proyecto sigue el flujo de trabajo definido en [PLAN.md](docs/PLAN.md) con 9 milestones (M0-M9).

Ver [issues en GitHub](https://github.com/cruizmol/urbanmoop-eventhound/issues) para tareas específicas.

## 📄 Licencia

[Especificar licencia]

## 🔗 Enlaces

- **Contratos:** [@urbanmoop/contracts](https://github.com/cruizmol/urbanmoop-contracts)
- **Issues:** [GitHub Issues](https://github.com/cruizmol/urbanmoop-eventhound/issues)
- **Milestones:** [GitHub Milestones](https://github.com/cruizmol/urbanmoop-eventhound/milestones)
