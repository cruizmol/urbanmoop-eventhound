# Eventhound - Migraciones de Base de Datos

## Índice

1. [Visión General](#visión-general)
2. [Orden de Ejecución](#orden-de-ejecución)
3. [Migraciones Existentes](#migraciones-existentes)
4. [Nuevas Migraciones](#nuevas-migraciones)
5. [Scripts de Verificación](#scripts-de-verificación)
6. [Rollback](#rollback)

---

## Visión General

Las migraciones del schema `webscraping` están organizadas en archivos SQL numerados que deben ejecutarse en orden secuencial debido a las dependencias entre tablas.

### Ubicación

```
eventhound/
└── migrations/
    └── webscraping/
        ├── 001_create_schema_and_basic_tables.sql
        ├── 002_create_content_tables.sql
        ├── 003_create_translation_tables.sql
        ├── 004_create_parsing_rules.sql
        ├── 005_populate_initial_data.sql
        ├── 006_add_processing_tracking.sql      # NUEVA
        ├── 007_add_classification_fields.sql    # NUEVA
        ├── 008_add_discovery_tracking.sql       # NUEVA
        ├── verify_sequence_permissions.sql
        └── rollback_complete.sql
```

---

## Orden de Ejecución

```bash
# Ejecutar migraciones en orden estricto
psql $DATABASE_URL -f migrations/webscraping/001_create_schema_and_basic_tables.sql
psql $DATABASE_URL -f migrations/webscraping/002_create_content_tables.sql
psql $DATABASE_URL -f migrations/webscraping/003_create_translation_tables.sql
psql $DATABASE_URL -f migrations/webscraping/004_create_parsing_rules.sql
psql $DATABASE_URL -f migrations/webscraping/005_populate_initial_data.sql
psql $DATABASE_URL -f migrations/webscraping/006_add_processing_tracking.sql
psql $DATABASE_URL -f migrations/webscraping/007_add_classification_fields.sql
psql $DATABASE_URL -f migrations/webscraping/008_add_discovery_tracking.sql

# Verificar permisos (opcional pero recomendado)
psql $DATABASE_URL -f migrations/webscraping/verify_sequence_permissions.sql
```

### Diagrama de Dependencias

```
001_create_schema_and_basic_tables
         │
         ├──────────────────┬──────────────────┐
         ▼                  ▼                  ▼
002_create_content    004_create_parsing   (independent)
         │                  │
         ▼                  │
003_create_translation      │
         │                  │
         └────────┬─────────┘
                  ▼
      005_populate_initial_data
                  │
                  ▼
      006_add_processing_tracking
                  │
                  ▼
      007_add_classification_fields
                  │
                  ▼
      008_add_discovery_tracking
```

---

## Migraciones Existentes

### 001_create_schema_and_basic_tables.sql

**Crea:**
- Schema `webscraping`
- Roles: `service_role`, `webscraper`
- Tablas base:
  - `alembic_version` - Control de versiones
  - `technology_templates` - Templates por CMS
  - `source_statuses` - Catálogo de estados
  - `source_status_transitions` - Transiciones permitidas
  - `sources` - Fuentes de datos
  - `source_status_history` - Histórico de cambios
  - `source_info` - Info de robots.txt
  - `venues` - Lugares
  - `organizers` - Organizadores
  - `event_categories` - Categorías
  - `age_groups` - Grupos de edad
  - `pages` - URLs rastreadas
  - `source_configs` - Configuraciones legacy
  - `source_configurations` - Configuraciones por sitio
  - `sitemap_discovery` - Sitemaps descubiertos
- Vista: `sources_with_info`
- Triggers: `update_updated_at_column()`

### 002_create_content_tables.sql

**Crea:**
- `events` - Eventos extraídos
- `posts` - Posts/artículos
- `post_categories` - Relación posts-categorías
- `related_links` - Enlaces relacionados

### 003_create_translation_tables.sql

**Crea:**
- `event_translations`
- `post_translations`
- `venue_translations`
- `organizer_translations`
- `event_category_translations`
- `age_group_translations`
- Función: `get_translation()`

### 004_create_parsing_rules.sql

**Crea:**
- `parsing_rules` - Reglas de extracción con soporte para templates

### 005_populate_initial_data.sql

**Inserta:**
- Datos iniciales de configuración
- Templates base
- Reglas de parsing por defecto

**NOTA:** Esta migración necesita corrección. Ver sección de nuevas migraciones.

---

## Nuevas Migraciones

### 006_add_processing_tracking.sql

Esta migración añade soporte para tracking de procesamiento y trazabilidad de eventos.

```sql
-- ============================================================================
-- MIGRACIÓN 006: Añadir Tracking de Procesamiento
-- Fecha: 2026-01-29
-- Descripción: Añade campos para correlación de mensajes, historial de
--              procesamiento y estados de página alineados con contratos
-- ============================================================================

-- ============================================================================
-- TABLA: page_statuses
-- Catálogo de estados posibles para páginas (alineado con contratos)
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.page_statuses (
    code VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT NOT NULL,
    is_terminal BOOLEAN DEFAULT false,
    is_error BOOLEAN DEFAULT false,
    display_order INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE webscraping.page_statuses IS 'Catálogo de estados posibles para páginas, alineado con eventos del sistema';
COMMENT ON COLUMN webscraping.page_statuses.is_terminal IS 'Indica si es un estado final (no hay transiciones salientes)';
COMMENT ON COLUMN webscraping.page_statuses.is_error IS 'Indica si es un estado de error';

-- Insertar estados alineados con el flujo de eventos
INSERT INTO webscraping.page_statuses (code, name, description, is_terminal, is_error, display_order) VALUES
('pending', 'Pendiente', 'En cola esperando procesamiento', false, false, 1),
('processing', 'Procesando', 'Scraping en progreso (evt.page.processing_started)', false, false, 2),
('scraped', 'Scrapeado', 'HTML obtenido exitosamente (evt.scrape.page.completed)', false, false, 3),
('scrape_failed', 'Scraping Fallido', 'Error al obtener HTML (evt.scrape.page.failed)', true, true, 4),
('classifying', 'Clasificando', 'Determinando si es evento (cmd.page.classify)', false, false, 5),
('classified_event', 'Es Evento', 'Clasificado como evento (evt.page.classified.event)', false, false, 6),
('classified_other', 'No es Evento', 'Clasificado como no-evento (evt.page.classified.other)', true, false, 7),
('extracting', 'Extrayendo', 'Extrayendo datos del evento (cmd.event.extract)', false, false, 8),
('processed', 'Procesado', 'Procesamiento completado exitosamente (evt.page.processed)', true, false, 9),
('extraction_failed', 'Extracción Fallida', 'Error al extraer datos', true, true, 10),
('duplicate', 'Duplicado', 'Evento duplicado detectado (evt.event.duplicate)', true, false, 11)
ON CONFLICT (code) DO NOTHING;

-- ============================================================================
-- MODIFICAR TABLA: pages
-- Añadir campos de tracking y correlación
-- ============================================================================

-- Campos de correlación con sistema de mensajes
ALTER TABLE webscraping.pages
ADD COLUMN IF NOT EXISTS correlation_id UUID,
ADD COLUMN IF NOT EXISTS last_message_id UUID,
ADD COLUMN IF NOT EXISTS last_message_type VARCHAR(100);

-- Campos de timestamps de procesamiento
ALTER TABLE webscraping.pages
ADD COLUMN IF NOT EXISTS processing_started_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS processing_completed_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS scrape_started_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS scrape_completed_at TIMESTAMPTZ;

-- Campos de metadata del scraping
ALTER TABLE webscraping.pages
ADD COLUMN IF NOT EXISTS response_time_ms INTEGER,
ADD COLUMN IF NOT EXISTS crawler_type VARCHAR(20),
ADD COLUMN IF NOT EXISTS retries_count INTEGER DEFAULT 0;

-- Campos de error
ALTER TABLE webscraping.pages
ADD COLUMN IF NOT EXISTS last_error_code VARCHAR(100),
ADD COLUMN IF NOT EXISTS last_error_message TEXT,
ADD COLUMN IF NOT EXISTS last_error_at TIMESTAMPTZ;

-- Modificar constraint de status para usar nuevo catálogo
-- Primero eliminar el constraint existente si existe
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'pages_status_check'
        AND table_schema = 'webscraping'
    ) THEN
        ALTER TABLE webscraping.pages DROP CONSTRAINT pages_status_check;
    END IF;
END $$;

-- Añadir foreign key al catálogo de estados
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_pages_status'
        AND table_schema = 'webscraping'
    ) THEN
        ALTER TABLE webscraping.pages
        ADD CONSTRAINT fk_pages_status
        FOREIGN KEY (status) REFERENCES webscraping.page_statuses(code);
    END IF;
END $$;

-- Índices para tracking
CREATE INDEX IF NOT EXISTS idx_pages_correlation_id
ON webscraping.pages(correlation_id)
WHERE correlation_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pages_last_message_type
ON webscraping.pages(last_message_type)
WHERE last_message_type IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pages_processing_started
ON webscraping.pages(processing_started_at DESC)
WHERE processing_started_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pages_errors
ON webscraping.pages(last_error_at DESC)
WHERE last_error_at IS NOT NULL;

-- ============================================================================
-- TABLA: page_processing_history
-- Historial completo de procesamiento para debugging y auditoría
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.page_processing_history (
    id BIGSERIAL PRIMARY KEY,
    page_id INTEGER NOT NULL REFERENCES webscraping.pages(id) ON DELETE CASCADE,

    -- Campos del envelope del mensaje
    message_id UUID NOT NULL,
    message_type VARCHAR(100) NOT NULL,
    schema_version INTEGER NOT NULL DEFAULT 1,
    correlation_id UUID,
    causation_id UUID,

    -- Transición de estado
    from_status VARCHAR(50) REFERENCES webscraping.page_statuses(code),
    to_status VARCHAR(50) NOT NULL REFERENCES webscraping.page_statuses(code),

    -- Metadata del procesamiento
    http_status INTEGER,
    response_time_ms INTEGER,
    content_length INTEGER,
    content_hash VARCHAR(64),
    crawler_type VARCHAR(20),

    -- Error (si aplica)
    error_code VARCHAR(100),
    error_message TEXT,
    error_details JSONB,

    -- Datos adicionales del evento
    event_payload JSONB,

    -- Timestamps
    occurred_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para page_processing_history
CREATE INDEX idx_page_processing_history_page_id
ON webscraping.page_processing_history(page_id);

CREATE INDEX idx_page_processing_history_correlation_id
ON webscraping.page_processing_history(correlation_id)
WHERE correlation_id IS NOT NULL;

CREATE INDEX idx_page_processing_history_message_type
ON webscraping.page_processing_history(message_type);

CREATE INDEX idx_page_processing_history_occurred_at
ON webscraping.page_processing_history(occurred_at DESC);

CREATE INDEX idx_page_processing_history_errors
ON webscraping.page_processing_history(error_code)
WHERE error_code IS NOT NULL;

-- Índice compuesto para queries de debugging
CREATE INDEX idx_page_processing_history_page_time
ON webscraping.page_processing_history(page_id, occurred_at DESC);

COMMENT ON TABLE webscraping.page_processing_history IS 'Historial de procesamiento de páginas - cada fila representa un evento del sistema';
COMMENT ON COLUMN webscraping.page_processing_history.message_id IS 'UUID del mensaje que causó esta entrada';
COMMENT ON COLUMN webscraping.page_processing_history.correlation_id IS 'ID de correlación para trazar todo el flujo de una página';
COMMENT ON COLUMN webscraping.page_processing_history.causation_id IS 'ID del mensaje que causó este evento (trazabilidad)';
COMMENT ON COLUMN webscraping.page_processing_history.event_payload IS 'Payload completo del evento para debugging';

-- ============================================================================
-- TABLA: page_status_transitions
-- Define las transiciones de estado permitidas para páginas
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.page_status_transitions (
    id SERIAL PRIMARY KEY,
    from_status VARCHAR(50) REFERENCES webscraping.page_statuses(code),
    to_status VARCHAR(50) NOT NULL REFERENCES webscraping.page_statuses(code),
    trigger_message_type VARCHAR(100) NOT NULL,
    is_automatic BOOLEAN DEFAULT true,
    description TEXT,
    UNIQUE(from_status, to_status)
);

COMMENT ON TABLE webscraping.page_status_transitions IS 'Define las transiciones de estado válidas y qué mensaje las dispara';
COMMENT ON COLUMN webscraping.page_status_transitions.trigger_message_type IS 'Tipo de mensaje que dispara esta transición';

-- Insertar transiciones válidas
INSERT INTO webscraping.page_status_transitions (from_status, to_status, trigger_message_type, description) VALUES
-- Desde pending
('pending', 'processing', 'evt.page.processing_started', 'Inicio de procesamiento'),

-- Desde processing
('processing', 'scraped', 'evt.scrape.page.completed', 'Scraping exitoso'),
('processing', 'scrape_failed', 'evt.scrape.page.failed', 'Error en scraping'),

-- Desde scraped
('scraped', 'classifying', 'cmd.page.classify', 'Inicio de clasificación'),

-- Desde classifying
('classifying', 'classified_event', 'evt.page.classified.event', 'Clasificado como evento'),
('classifying', 'classified_other', 'evt.page.classified.other', 'Clasificado como no-evento'),

-- Desde classified_event
('classified_event', 'extracting', 'cmd.event.extract', 'Inicio de extracción'),

-- Desde extracting
('extracting', 'processed', 'evt.event.extracted', 'Extracción exitosa'),
('extracting', 'duplicate', 'evt.event.duplicate', 'Evento duplicado'),
('extracting', 'extraction_failed', 'evt.event.extraction_failed', 'Error en extracción'),

-- Retry desde errores (transiciones manuales)
('scrape_failed', 'pending', 'cmd.page.retry', 'Reintentar scraping'),
('extraction_failed', 'classified_event', 'cmd.page.retry', 'Reintentar extracción')
ON CONFLICT (from_status, to_status) DO NOTHING;

-- ============================================================================
-- FUNCIÓN: Validar transición de estado
-- ============================================================================
CREATE OR REPLACE FUNCTION webscraping.validate_page_status_transition()
RETURNS TRIGGER AS $$
DECLARE
    transition_valid BOOLEAN;
BEGIN
    -- Si es INSERT, solo validar que el estado inicial sea válido
    IF TG_OP = 'INSERT' THEN
        IF NEW.status != 'pending' THEN
            RAISE EXCEPTION 'Estado inicial debe ser "pending", recibido: %', NEW.status;
        END IF;
        RETURN NEW;
    END IF;

    -- Si es UPDATE y el status no cambió, permitir
    IF OLD.status = NEW.status THEN
        RETURN NEW;
    END IF;

    -- Validar que la transición existe
    SELECT EXISTS (
        SELECT 1 FROM webscraping.page_status_transitions
        WHERE from_status = OLD.status AND to_status = NEW.status
    ) INTO transition_valid;

    IF NOT transition_valid THEN
        RAISE EXCEPTION 'Transición de estado no permitida: % -> %', OLD.status, NEW.status;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Aplicar trigger (deshabilitado por defecto para permitir migraciones de datos)
-- Habilitar después de la migración inicial:
-- CREATE TRIGGER validate_page_status_transition_trigger
--     BEFORE INSERT OR UPDATE ON webscraping.pages
--     FOR EACH ROW EXECUTE FUNCTION webscraping.validate_page_status_transition();

-- ============================================================================
-- VISTA: Resumen de procesamiento por source
-- ============================================================================
CREATE OR REPLACE VIEW webscraping.source_processing_stats AS
SELECT
    s.id as source_id,
    s.name as source_name,
    s.status as source_status,
    COUNT(p.id) as total_pages,
    COUNT(p.id) FILTER (WHERE p.status = 'pending') as pending_pages,
    COUNT(p.id) FILTER (WHERE p.status = 'processing') as processing_pages,
    COUNT(p.id) FILTER (WHERE p.status = 'processed') as processed_pages,
    COUNT(p.id) FILTER (WHERE ps.is_error = true) as error_pages,
    AVG(p.response_time_ms) FILTER (WHERE p.response_time_ms IS NOT NULL) as avg_response_time_ms,
    MAX(p.processing_completed_at) as last_processed_at
FROM webscraping.sources s
LEFT JOIN webscraping.pages p ON s.id = p.source_id
LEFT JOIN webscraping.page_statuses ps ON p.status = ps.code
GROUP BY s.id, s.name, s.status;

COMMENT ON VIEW webscraping.source_processing_stats IS 'Estadísticas de procesamiento agregadas por source';

-- ============================================================================
-- PERMISOS
-- ============================================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON webscraping.page_statuses TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON webscraping.page_processing_history TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON webscraping.page_status_transitions TO service_role;
GRANT USAGE, SELECT ON SEQUENCE webscraping.page_processing_history_id_seq TO service_role;
GRANT USAGE, SELECT ON SEQUENCE webscraping.page_status_transitions_id_seq TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON webscraping.page_statuses TO webscraper;
GRANT SELECT, INSERT, UPDATE, DELETE ON webscraping.page_processing_history TO webscraper;
GRANT SELECT, INSERT, UPDATE, DELETE ON webscraping.page_status_transitions TO webscraper;
GRANT USAGE, SELECT ON SEQUENCE webscraping.page_processing_history_id_seq TO webscraper;
GRANT USAGE, SELECT ON SEQUENCE webscraping.page_status_transitions_id_seq TO webscraper;
```

---

### 007_add_classification_fields.sql

Esta migración añade soporte para clasificación de páginas y extracción de datos.

```sql
-- ============================================================================
-- MIGRACIÓN 007: Añadir Campos de Clasificación y Extracción
-- Fecha: 2026-01-29
-- Descripción: Añade campos para almacenar resultados de clasificación,
--              datos extraídos y metadata de procesamiento
-- ============================================================================

-- ============================================================================
-- MODIFICAR TABLA: pages
-- Añadir campos de clasificación
-- ============================================================================

-- Campos de clasificación
ALTER TABLE webscraping.pages
ADD COLUMN IF NOT EXISTS is_event BOOLEAN,
ADD COLUMN IF NOT EXISTS classification_score FLOAT,
ADD COLUMN IF NOT EXISTS classification_method VARCHAR(50),
ADD COLUMN IF NOT EXISTS classification_reason TEXT,
ADD COLUMN IF NOT EXISTS classified_at TIMESTAMPTZ;

-- Campos de extracción preliminar (antes de crear evento)
ALTER TABLE webscraping.pages
ADD COLUMN IF NOT EXISTS extracted_title VARCHAR(500),
ADD COLUMN IF NOT EXISTS extracted_date_text VARCHAR(200),
ADD COLUMN IF NOT EXISTS extraction_metadata JSONB;

-- Check constraint para classification_score
ALTER TABLE webscraping.pages
ADD CONSTRAINT check_classification_score
CHECK (classification_score IS NULL OR (classification_score >= 0 AND classification_score <= 1));

-- Check constraint para classification_method
ALTER TABLE webscraping.pages
ADD CONSTRAINT check_classification_method
CHECK (classification_method IS NULL OR classification_method IN ('rule_based', 'ml_model', 'hybrid', 'manual'));

-- Índices para clasificación
CREATE INDEX IF NOT EXISTS idx_pages_is_event
ON webscraping.pages(is_event)
WHERE is_event = true;

CREATE INDEX IF NOT EXISTS idx_pages_classification_score
ON webscraping.pages(classification_score DESC)
WHERE classification_score IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pages_classification_method
ON webscraping.pages(classification_method)
WHERE classification_method IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pages_classified_at
ON webscraping.pages(classified_at DESC)
WHERE classified_at IS NOT NULL;

-- Índice compuesto para queries de eventos pendientes de extracción
CREATE INDEX IF NOT EXISTS idx_pages_pending_extraction
ON webscraping.pages(source_id, classified_at)
WHERE is_event = true AND status = 'classified_event';

COMMENT ON COLUMN webscraping.pages.is_event IS 'Resultado de clasificación: true si es evento, false si no';
COMMENT ON COLUMN webscraping.pages.classification_score IS 'Confianza de la clasificación (0.0 a 1.0)';
COMMENT ON COLUMN webscraping.pages.classification_method IS 'Método usado: rule_based, ml_model, hybrid, manual';
COMMENT ON COLUMN webscraping.pages.classification_reason IS 'Explicación de por qué se clasificó así';
COMMENT ON COLUMN webscraping.pages.extracted_title IS 'Título extraído preliminarmente (para preview)';
COMMENT ON COLUMN webscraping.pages.extraction_metadata IS 'Metadata de la extracción (selectores usados, etc.)';

-- ============================================================================
-- TABLA: classification_rules
-- Reglas para clasificación rule-based
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.classification_rules (
    id SERIAL PRIMARY KEY,
    source_id INTEGER REFERENCES webscraping.sources(id) ON DELETE CASCADE,
    technology_template_id INTEGER REFERENCES webscraping.technology_templates(id) ON DELETE SET NULL,

    -- Regla
    rule_name VARCHAR(100) NOT NULL,
    rule_type VARCHAR(50) NOT NULL, -- 'url_pattern', 'css_selector', 'meta_tag', 'schema_org'
    rule_config JSONB NOT NULL,

    -- Resultado si match
    is_event_if_match BOOLEAN NOT NULL DEFAULT true,
    score_if_match FLOAT NOT NULL DEFAULT 1.0,

    -- Metadata
    priority INTEGER NOT NULL DEFAULT 100,
    is_active BOOLEAN NOT NULL DEFAULT true,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Constraint
    CONSTRAINT check_score_range CHECK (score_if_match >= 0 AND score_if_match <= 1)
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_classification_rules_source
ON webscraping.classification_rules(source_id)
WHERE source_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_classification_rules_template
ON webscraping.classification_rules(technology_template_id)
WHERE technology_template_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_classification_rules_active
ON webscraping.classification_rules(is_active, priority)
WHERE is_active = true;

COMMENT ON TABLE webscraping.classification_rules IS 'Reglas para clasificar páginas como eventos o no-eventos';
COMMENT ON COLUMN webscraping.classification_rules.rule_type IS 'Tipo de regla: url_pattern, css_selector, meta_tag, schema_org';
COMMENT ON COLUMN webscraping.classification_rules.rule_config IS 'Configuración de la regla en formato JSON';
COMMENT ON COLUMN webscraping.classification_rules.priority IS 'Prioridad de evaluación (menor = más prioritario)';

-- Trigger para updated_at
CREATE TRIGGER update_classification_rules_updated_at
    BEFORE UPDATE ON webscraping.classification_rules
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

-- ============================================================================
-- INSERTAR REGLAS DE CLASIFICACIÓN POR DEFECTO
-- ============================================================================
INSERT INTO webscraping.classification_rules (rule_name, rule_type, rule_config, is_event_if_match, score_if_match, priority, description) VALUES
-- Reglas de URL
('URL contiene /event/', 'url_pattern', '{"pattern": "/event/"}', true, 0.9, 10, 'URLs con /event/ en el path'),
('URL contiene /events/', 'url_pattern', '{"pattern": "/events/"}', true, 0.9, 10, 'URLs con /events/ en el path'),
('URL contiene /actividad/', 'url_pattern', '{"pattern": "/actividad/"}', true, 0.9, 10, 'URLs con /actividad/ (español)'),
('URL contiene /actividades/', 'url_pattern', '{"pattern": "/actividades/"}', true, 0.9, 10, 'URLs con /actividades/ (español)'),
('URL contiene /agenda/', 'url_pattern', '{"pattern": "/agenda/"}', true, 0.8, 20, 'URLs con /agenda/'),

-- Reglas de Schema.org
('Schema.org Event', 'schema_org', '{"type": "Event"}', true, 1.0, 5, 'Página con Schema.org Event'),
('Schema.org MusicEvent', 'schema_org', '{"type": "MusicEvent"}', true, 1.0, 5, 'Página con Schema.org MusicEvent'),
('Schema.org TheaterEvent', 'schema_org', '{"type": "TheaterEvent"}', true, 1.0, 5, 'Página con Schema.org TheaterEvent'),
('Schema.org SportsEvent', 'schema_org', '{"type": "SportsEvent"}', true, 1.0, 5, 'Página con Schema.org SportsEvent'),

-- Reglas de meta tags
('Meta og:type event', 'meta_tag', '{"name": "og:type", "value": "event"}', true, 0.95, 8, 'Open Graph type = event'),

-- Reglas negativas (no son eventos)
('URL es listado /page/', 'url_pattern', '{"pattern": "/page/\\d+"}', false, 0.1, 100, 'Páginas de paginación'),
('URL es categoría', 'url_pattern', '{"pattern": "/category/"}', false, 0.2, 100, 'Páginas de categoría'),
('URL es tag', 'url_pattern', '{"pattern": "/tag/"}', false, 0.2, 100, 'Páginas de tag'),
('URL es búsqueda', 'url_pattern', '{"pattern": "/search"}', false, 0.1, 100, 'Páginas de búsqueda')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- MODIFICAR TABLA: events
-- Añadir campos adicionales para tracking
-- ============================================================================

-- Campo para vincular con la página origen
ALTER TABLE webscraping.events
ADD COLUMN IF NOT EXISTS page_id INTEGER REFERENCES webscraping.pages(id) ON DELETE SET NULL;

-- Campos de trazabilidad
ALTER TABLE webscraping.events
ADD COLUMN IF NOT EXISTS correlation_id UUID,
ADD COLUMN IF NOT EXISTS extraction_message_id UUID;

-- Campos de calidad de datos
ALTER TABLE webscraping.events
ADD COLUMN IF NOT EXISTS data_quality_score FLOAT,
ADD COLUMN IF NOT EXISTS extraction_confidence FLOAT,
ADD COLUMN IF NOT EXISTS extraction_method VARCHAR(50);

-- Índices
CREATE INDEX IF NOT EXISTS idx_events_page_id
ON webscraping.events(page_id)
WHERE page_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_events_correlation_id
ON webscraping.events(correlation_id)
WHERE correlation_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_events_data_quality
ON webscraping.events(data_quality_score DESC)
WHERE data_quality_score IS NOT NULL;

COMMENT ON COLUMN webscraping.events.page_id IS 'Página de la que se extrajo este evento';
COMMENT ON COLUMN webscraping.events.correlation_id IS 'ID de correlación del flujo de procesamiento';
COMMENT ON COLUMN webscraping.events.data_quality_score IS 'Puntuación de calidad de datos (0-1)';
COMMENT ON COLUMN webscraping.events.extraction_confidence IS 'Confianza en la extracción (0-1)';

-- ============================================================================
-- TABLA: duplicate_events
-- Registro de eventos duplicados detectados
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.duplicate_events (
    id BIGSERIAL PRIMARY KEY,
    page_id INTEGER NOT NULL REFERENCES webscraping.pages(id) ON DELETE CASCADE,
    original_event_id INTEGER NOT NULL REFERENCES webscraping.events(id) ON DELETE CASCADE,

    -- Razón de duplicado
    duplicate_reason VARCHAR(50) NOT NULL, -- 'same_url', 'same_title_date', 'fuzzy_match'
    similarity_score FLOAT,

    -- Trazabilidad
    correlation_id UUID,
    message_id UUID,

    -- Timestamps
    detected_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_duplicate_events_page
ON webscraping.duplicate_events(page_id);

CREATE INDEX idx_duplicate_events_original
ON webscraping.duplicate_events(original_event_id);

CREATE INDEX idx_duplicate_events_detected
ON webscraping.duplicate_events(detected_at DESC);

COMMENT ON TABLE webscraping.duplicate_events IS 'Registro de eventos duplicados para auditoría';

-- ============================================================================
-- VISTA: Eventos con información de extracción
-- ============================================================================
CREATE OR REPLACE VIEW webscraping.events_with_extraction_info AS
SELECT
    e.*,
    p.url as source_url,
    p.classification_score,
    p.classification_method,
    p.processing_started_at,
    p.processing_completed_at,
    s.name as source_name,
    s.base_url as source_base_url
FROM webscraping.events e
LEFT JOIN webscraping.pages p ON e.page_id = p.id
LEFT JOIN webscraping.sources s ON e.source_id = s.id;

COMMENT ON VIEW webscraping.events_with_extraction_info IS 'Eventos con información completa de extracción y source';

-- ============================================================================
-- FUNCIÓN: Calcular score de calidad de datos
-- ============================================================================
CREATE OR REPLACE FUNCTION webscraping.calculate_data_quality_score(
    p_event_id INTEGER
) RETURNS FLOAT AS $$
DECLARE
    v_score FLOAT := 0;
    v_event RECORD;
BEGIN
    SELECT * INTO v_event FROM webscraping.events WHERE id = p_event_id;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    -- Título presente y longitud razonable
    IF v_event.title IS NOT NULL AND LENGTH(v_event.title) > 10 THEN
        v_score := v_score + 0.2;
    END IF;

    -- Descripción presente
    IF v_event.description IS NOT NULL AND LENGTH(v_event.description) > 50 THEN
        v_score := v_score + 0.15;
    END IF;

    -- Fecha de inicio presente
    IF v_event.starts_at IS NOT NULL THEN
        v_score := v_score + 0.25;
    END IF;

    -- Venue presente
    IF v_event.venue_id IS NOT NULL THEN
        v_score := v_score + 0.15;
    END IF;

    -- URL de imagen presente
    IF v_event.image_url IS NOT NULL THEN
        v_score := v_score + 0.1;
    END IF;

    -- Precio presente
    IF v_event.price_type IS NOT NULL THEN
        v_score := v_score + 0.1;
    END IF;

    -- Categoría presente
    IF v_event.event_category_id IS NOT NULL THEN
        v_score := v_score + 0.05;
    END IF;

    RETURN LEAST(v_score, 1.0);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION webscraping.calculate_data_quality_score IS 'Calcula puntuación de calidad de datos para un evento';

-- ============================================================================
-- PERMISOS
-- ============================================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON webscraping.classification_rules TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON webscraping.duplicate_events TO service_role;
GRANT USAGE, SELECT ON SEQUENCE webscraping.classification_rules_id_seq TO service_role;
GRANT USAGE, SELECT ON SEQUENCE webscraping.duplicate_events_id_seq TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON webscraping.classification_rules TO webscraper;
GRANT SELECT, INSERT, UPDATE, DELETE ON webscraping.duplicate_events TO webscraper;
GRANT USAGE, SELECT ON SEQUENCE webscraping.classification_rules_id_seq TO webscraper;
GRANT USAGE, SELECT ON SEQUENCE webscraping.duplicate_events_id_seq TO webscraper;
```

---

### 008_add_discovery_tracking.sql

Esta migración añade soporte para tracking de descubrimiento multi-estrategia.

```sql
-- ============================================================================
-- MIGRACIÓN 008: Añadir Tracking de Descubrimiento
-- Fecha: 2026-01-30
-- Descripción: Añade tablas y campos para soportar múltiples estrategias de
--              descubrimiento de URLs (sitemap, link crawling, RSS, patterns)
-- ============================================================================

-- ============================================================================
-- TIPO ENUM: discovery_strategy
-- Estrategias de descubrimiento disponibles
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'discovery_strategy') THEN
        CREATE TYPE webscraping.discovery_strategy AS ENUM (
            'sitemap',       -- Descubrimiento via sitemap.xml
            'link_crawl',    -- Crawling de enlaces internos
            'rss_feed',      -- Feeds RSS/Atom
            'url_pattern',   -- Patrones de URL conocidos
            'hybrid'         -- Combinación de estrategias
        );
    END IF;
END $$;

-- ============================================================================
-- TIPO ENUM: discovery_run_status
-- Estados de una ejecución de descubrimiento
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'discovery_run_status') THEN
        CREATE TYPE webscraping.discovery_run_status AS ENUM (
            'pending',       -- Pendiente de iniciar
            'running',       -- En progreso
            'completed',     -- Completado exitosamente
            'failed',        -- Falló
            'cancelled'      -- Cancelado
        );
    END IF;
END $$;

-- ============================================================================
-- TABLA: discovery_runs
-- Registro de ejecuciones de descubrimiento
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.discovery_runs (
    id BIGSERIAL PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES webscraping.sources(id) ON DELETE CASCADE,

    -- Configuración
    strategy webscraping.discovery_strategy NOT NULL,
    config JSONB NOT NULL DEFAULT '{}',

    -- Estado
    status webscraping.discovery_run_status NOT NULL DEFAULT 'pending',

    -- Trazabilidad
    correlation_id UUID NOT NULL,
    triggered_by VARCHAR(100), -- 'scheduler', 'manual', 'webhook'

    -- Estadísticas
    urls_discovered INTEGER DEFAULT 0,
    urls_queued INTEGER DEFAULT 0,
    urls_filtered INTEGER DEFAULT 0,
    urls_duplicate INTEGER DEFAULT 0,

    -- Progreso (para estrategias multi-fase)
    current_phase VARCHAR(50),
    phase_progress JSONB,

    -- Timing
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,

    -- Errores
    error_code VARCHAR(100),
    error_message TEXT,
    error_details JSONB,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para discovery_runs
CREATE INDEX IF NOT EXISTS idx_discovery_runs_source
ON webscraping.discovery_runs(source_id);

CREATE INDEX IF NOT EXISTS idx_discovery_runs_status
ON webscraping.discovery_runs(status)
WHERE status IN ('pending', 'running');

CREATE INDEX IF NOT EXISTS idx_discovery_runs_correlation
ON webscraping.discovery_runs(correlation_id);

CREATE INDEX IF NOT EXISTS idx_discovery_runs_started
ON webscraping.discovery_runs(started_at DESC)
WHERE started_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_discovery_runs_source_strategy
ON webscraping.discovery_runs(source_id, strategy, started_at DESC);

-- Trigger para updated_at
CREATE TRIGGER update_discovery_runs_updated_at
    BEFORE UPDATE ON webscraping.discovery_runs
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

COMMENT ON TABLE webscraping.discovery_runs IS 'Registro de ejecuciones de descubrimiento de URLs';
COMMENT ON COLUMN webscraping.discovery_runs.strategy IS 'Estrategia usada: sitemap, link_crawl, rss_feed, url_pattern, hybrid';
COMMENT ON COLUMN webscraping.discovery_runs.config IS 'Configuración específica de la estrategia';
COMMENT ON COLUMN webscraping.discovery_runs.phase_progress IS 'Progreso por fase para estrategias complejas';

-- ============================================================================
-- TABLA: discovered_urls
-- URLs descubiertas en cada run
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.discovered_urls (
    id BIGSERIAL PRIMARY KEY,
    discovery_run_id BIGINT NOT NULL REFERENCES webscraping.discovery_runs(id) ON DELETE CASCADE,

    -- URL descubierta
    url TEXT NOT NULL,
    url_hash VARCHAR(64) NOT NULL, -- SHA256 para deduplicación rápida

    -- Origen del descubrimiento
    discovered_from VARCHAR(50) NOT NULL, -- 'sitemap', 'link', 'rss', 'pattern'
    source_url TEXT, -- URL desde donde se descubrió (para links)

    -- Metadata del sitemap (si aplica)
    lastmod TIMESTAMPTZ,
    priority FLOAT,
    changefreq VARCHAR(20),

    -- Estado
    was_queued BOOLEAN DEFAULT false,
    was_filtered BOOLEAN DEFAULT false,
    filter_reason VARCHAR(100),
    was_duplicate BOOLEAN DEFAULT false,
    existing_page_id INTEGER REFERENCES webscraping.pages(id),

    -- Timestamps
    discovered_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para discovered_urls
CREATE INDEX IF NOT EXISTS idx_discovered_urls_run
ON webscraping.discovered_urls(discovery_run_id);

CREATE INDEX IF NOT EXISTS idx_discovered_urls_hash
ON webscraping.discovered_urls(url_hash);

CREATE INDEX IF NOT EXISTS idx_discovered_urls_queued
ON webscraping.discovered_urls(discovery_run_id, was_queued)
WHERE was_queued = true;

COMMENT ON TABLE webscraping.discovered_urls IS 'URLs individuales descubiertas en cada run de discovery';
COMMENT ON COLUMN webscraping.discovered_urls.url_hash IS 'Hash SHA256 de la URL para deduplicación eficiente';
COMMENT ON COLUMN webscraping.discovered_urls.filter_reason IS 'Razón por la que se filtró (robots_blocked, pattern_excluded, etc.)';

-- ============================================================================
-- MODIFICAR TABLA: pages
-- Añadir campos de descubrimiento
-- ============================================================================

-- Campo para saber cómo se descubrió la página
ALTER TABLE webscraping.pages
ADD COLUMN IF NOT EXISTS discovered_by webscraping.discovery_strategy,
ADD COLUMN IF NOT EXISTS discovery_run_id BIGINT REFERENCES webscraping.discovery_runs(id),
ADD COLUMN IF NOT EXISTS discovered_from_url TEXT;

-- Índice para análisis de descubrimiento
CREATE INDEX IF NOT EXISTS idx_pages_discovered_by
ON webscraping.pages(discovered_by)
WHERE discovered_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pages_discovery_run
ON webscraping.pages(discovery_run_id)
WHERE discovery_run_id IS NOT NULL;

COMMENT ON COLUMN webscraping.pages.discovered_by IS 'Estrategia que descubrió esta URL';
COMMENT ON COLUMN webscraping.pages.discovery_run_id IS 'Run de discovery que encontró esta URL';
COMMENT ON COLUMN webscraping.pages.discovered_from_url IS 'URL desde donde se descubrió (para link crawling)';

-- ============================================================================
-- MODIFICAR TABLA: source_configurations
-- Añadir configuración de discovery
-- ============================================================================

ALTER TABLE webscraping.source_configurations
ADD COLUMN IF NOT EXISTS discovery_config JSONB DEFAULT '{}';

COMMENT ON COLUMN webscraping.source_configurations.discovery_config IS 'Configuración de estrategias de descubrimiento';

-- ============================================================================
-- TABLA: discovery_schedules
-- Programación de descubrimientos automáticos
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.discovery_schedules (
    id SERIAL PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES webscraping.sources(id) ON DELETE CASCADE,

    -- Configuración
    strategy webscraping.discovery_strategy NOT NULL,
    config JSONB NOT NULL DEFAULT '{}',

    -- Programación (cron-like)
    schedule_cron VARCHAR(100) NOT NULL, -- '0 2 * * *' = cada día a las 2am
    timezone VARCHAR(50) DEFAULT 'Europe/Madrid',

    -- Estado
    is_active BOOLEAN DEFAULT true,

    -- Última ejecución
    last_run_id BIGINT REFERENCES webscraping.discovery_runs(id),
    last_run_at TIMESTAMPTZ,
    next_run_at TIMESTAMPTZ,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Una sola programación por source+strategy
    UNIQUE(source_id, strategy)
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_discovery_schedules_next_run
ON webscraping.discovery_schedules(next_run_at)
WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_discovery_schedules_source
ON webscraping.discovery_schedules(source_id);

-- Trigger para updated_at
CREATE TRIGGER update_discovery_schedules_updated_at
    BEFORE UPDATE ON webscraping.discovery_schedules
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

COMMENT ON TABLE webscraping.discovery_schedules IS 'Programación de descubrimientos automáticos por source';
COMMENT ON COLUMN webscraping.discovery_schedules.schedule_cron IS 'Expresión cron para programación';

-- ============================================================================
-- VISTA: discovery_stats
-- Estadísticas de descubrimiento por source
-- ============================================================================
CREATE OR REPLACE VIEW webscraping.discovery_stats AS
SELECT
    s.id as source_id,
    s.name as source_name,
    dr.strategy,
    COUNT(dr.id) as total_runs,
    COUNT(dr.id) FILTER (WHERE dr.status = 'completed') as successful_runs,
    COUNT(dr.id) FILTER (WHERE dr.status = 'failed') as failed_runs,
    SUM(dr.urls_discovered) as total_urls_discovered,
    SUM(dr.urls_queued) as total_urls_queued,
    AVG(EXTRACT(EPOCH FROM (dr.completed_at - dr.started_at))) as avg_duration_seconds,
    MAX(dr.started_at) as last_run_at,
    MAX(dr.completed_at) FILTER (WHERE dr.status = 'completed') as last_successful_run_at
FROM webscraping.sources s
LEFT JOIN webscraping.discovery_runs dr ON s.id = dr.source_id
GROUP BY s.id, s.name, dr.strategy;

COMMENT ON VIEW webscraping.discovery_stats IS 'Estadísticas agregadas de descubrimiento por source y estrategia';

-- ============================================================================
-- FUNCIÓN: Calcular siguiente ejecución programada
-- ============================================================================
CREATE OR REPLACE FUNCTION webscraping.calculate_next_discovery_run(
    p_schedule_cron VARCHAR,
    p_timezone VARCHAR DEFAULT 'Europe/Madrid'
) RETURNS TIMESTAMPTZ AS $$
DECLARE
    v_now TIMESTAMPTZ;
    v_next TIMESTAMPTZ;
BEGIN
    -- Por ahora retorna una hora desde ahora
    -- En producción, usar pg_cron o librería de parsing cron
    v_now := NOW() AT TIME ZONE p_timezone;
    v_next := v_now + INTERVAL '1 hour';
    RETURN v_next AT TIME ZONE p_timezone;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION webscraping.calculate_next_discovery_run IS 'Calcula próxima ejecución basada en cron (placeholder)';

-- ============================================================================
-- PERMISOS
-- ============================================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON webscraping.discovery_runs TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON webscraping.discovered_urls TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON webscraping.discovery_schedules TO service_role;
GRANT USAGE, SELECT ON SEQUENCE webscraping.discovery_runs_id_seq TO service_role;
GRANT USAGE, SELECT ON SEQUENCE webscraping.discovered_urls_id_seq TO service_role;
GRANT USAGE, SELECT ON SEQUENCE webscraping.discovery_schedules_id_seq TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON webscraping.discovery_runs TO webscraper;
GRANT SELECT, INSERT, UPDATE, DELETE ON webscraping.discovered_urls TO webscraper;
GRANT SELECT, INSERT, UPDATE, DELETE ON webscraping.discovery_schedules TO webscraper;
GRANT USAGE, SELECT ON SEQUENCE webscraping.discovery_runs_id_seq TO webscraper;
GRANT USAGE, SELECT ON SEQUENCE webscraping.discovered_urls_id_seq TO webscraper;
GRANT USAGE, SELECT ON SEQUENCE webscraping.discovery_schedules_id_seq TO webscraper;
```

---

### rollback_008.sql

```sql
-- Rollback de migración 008
DROP VIEW IF EXISTS webscraping.discovery_stats CASCADE;
DROP FUNCTION IF EXISTS webscraping.calculate_next_discovery_run CASCADE;
DROP TABLE IF EXISTS webscraping.discovery_schedules CASCADE;
DROP TABLE IF EXISTS webscraping.discovered_urls CASCADE;
DROP TABLE IF EXISTS webscraping.discovery_runs CASCADE;

ALTER TABLE webscraping.pages
DROP COLUMN IF EXISTS discovered_by,
DROP COLUMN IF EXISTS discovery_run_id,
DROP COLUMN IF EXISTS discovered_from_url;

ALTER TABLE webscraping.source_configurations
DROP COLUMN IF EXISTS discovery_config;

DROP TYPE IF EXISTS webscraping.discovery_run_status CASCADE;
DROP TYPE IF EXISTS webscraping.discovery_strategy CASCADE;
```

---

## Scripts de Verificación

### verify_all_migrations.sql

```sql
-- ============================================================================
-- Script de verificación completa de migraciones
-- ============================================================================

-- Verificar todas las tablas existen
DO $$
DECLARE
    expected_tables TEXT[] := ARRAY[
        'alembic_version',
        'technology_templates',
        'source_statuses',
        'source_status_transitions',
        'sources',
        'source_status_history',
        'source_info',
        'venues',
        'organizers',
        'event_categories',
        'age_groups',
        'pages',
        'source_configs',
        'source_configurations',
        'sitemap_discovery',
        'events',
        'posts',
        'post_categories',
        'related_links',
        'event_translations',
        'post_translations',
        'venue_translations',
        'organizer_translations',
        'event_category_translations',
        'age_group_translations',
        'parsing_rules',
        'page_statuses',
        'page_processing_history',
        'page_status_transitions',
        'classification_rules',
        'duplicate_events',
        'discovery_runs',
        'discovered_urls',
        'discovery_schedules'
    ];
    missing_tables TEXT[] := ARRAY[]::TEXT[];
    t TEXT;
BEGIN
    FOREACH t IN ARRAY expected_tables
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'webscraping' AND table_name = t
        ) THEN
            missing_tables := array_append(missing_tables, t);
        END IF;
    END LOOP;

    IF array_length(missing_tables, 1) > 0 THEN
        RAISE EXCEPTION 'Tablas faltantes: %', array_to_string(missing_tables, ', ');
    ELSE
        RAISE NOTICE '✅ Todas las tablas existen';
    END IF;
END $$;

-- Verificar índices críticos
SELECT
    CASE
        WHEN COUNT(*) >= 10 THEN '✅ Índices críticos presentes'
        ELSE '❌ Faltan índices críticos'
    END as status,
    COUNT(*) as total_indexes
FROM pg_indexes
WHERE schemaname = 'webscraping'
AND indexname IN (
    'idx_pages_status_next_crawl',
    'idx_pages_correlation_id',
    'idx_pages_is_event',
    'idx_page_processing_history_correlation_id',
    'idx_events_starts_at',
    'idx_events_page_id'
);

-- Verificar foreign keys
SELECT
    tc.table_name,
    tc.constraint_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
AND tc.table_schema = 'webscraping'
ORDER BY tc.table_name;

-- Verificar estados de página
SELECT
    '✅ Estados de página: ' || COUNT(*) || ' registros' as status
FROM webscraping.page_statuses;

-- Verificar transiciones de estado
SELECT
    '✅ Transiciones de página: ' || COUNT(*) || ' registros' as status
FROM webscraping.page_status_transitions;

-- Verificar reglas de clasificación
SELECT
    '✅ Reglas de clasificación: ' || COUNT(*) || ' registros' as status
FROM webscraping.classification_rules;

-- Resumen final
SELECT '====== VERIFICACIÓN COMPLETA ======' as message;
```

---

## Rollback

### rollback_007.sql

```sql
-- Rollback de migración 007
DROP TABLE IF EXISTS webscraping.duplicate_events CASCADE;
DROP TABLE IF EXISTS webscraping.classification_rules CASCADE;
DROP VIEW IF EXISTS webscraping.events_with_extraction_info CASCADE;
DROP FUNCTION IF EXISTS webscraping.calculate_data_quality_score CASCADE;

ALTER TABLE webscraping.pages
DROP COLUMN IF EXISTS is_event,
DROP COLUMN IF EXISTS classification_score,
DROP COLUMN IF EXISTS classification_method,
DROP COLUMN IF EXISTS classification_reason,
DROP COLUMN IF EXISTS classified_at,
DROP COLUMN IF EXISTS extracted_title,
DROP COLUMN IF EXISTS extracted_date_text,
DROP COLUMN IF EXISTS extraction_metadata;

ALTER TABLE webscraping.events
DROP COLUMN IF EXISTS page_id,
DROP COLUMN IF EXISTS correlation_id,
DROP COLUMN IF EXISTS extraction_message_id,
DROP COLUMN IF EXISTS data_quality_score,
DROP COLUMN IF EXISTS extraction_confidence,
DROP COLUMN IF EXISTS extraction_method;
```

### rollback_006.sql

```sql
-- Rollback de migración 006
DROP VIEW IF EXISTS webscraping.source_processing_stats CASCADE;
DROP TABLE IF EXISTS webscraping.page_status_transitions CASCADE;
DROP TABLE IF EXISTS webscraping.page_processing_history CASCADE;
DROP TABLE IF EXISTS webscraping.page_statuses CASCADE;
DROP FUNCTION IF EXISTS webscraping.validate_page_status_transition CASCADE;

ALTER TABLE webscraping.pages
DROP COLUMN IF EXISTS correlation_id,
DROP COLUMN IF EXISTS last_message_id,
DROP COLUMN IF EXISTS last_message_type,
DROP COLUMN IF EXISTS processing_started_at,
DROP COLUMN IF EXISTS processing_completed_at,
DROP COLUMN IF EXISTS scrape_started_at,
DROP COLUMN IF EXISTS scrape_completed_at,
DROP COLUMN IF EXISTS response_time_ms,
DROP COLUMN IF EXISTS crawler_type,
DROP COLUMN IF EXISTS retries_count,
DROP COLUMN IF EXISTS last_error_code,
DROP COLUMN IF EXISTS last_error_message,
DROP COLUMN IF EXISTS last_error_at;
```

---

## Referencias

- [Arquitectura del Proyecto](./ARCHITECTURE.md)
- [Especificación de Contratos](./CONTRACTS.md)
