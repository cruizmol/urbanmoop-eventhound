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
