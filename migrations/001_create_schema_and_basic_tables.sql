-- ============================================================================
-- MIGRACIÓN 001: Crear Schema Webscraping y Tablas Básicas
-- Fecha: 2025-11-27
-- Descripción: Crea el schema webscraping y las tablas principales
-- ============================================================================

-- Crear schema webscraping si no existe
CREATE SCHEMA IF NOT EXISTS webscraping;

-- Dar permisos a service_role
GRANT USAGE ON SCHEMA webscraping TO service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA webscraping
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA webscraping
GRANT USAGE, SELECT ON SEQUENCES TO service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA webscraping
GRANT EXECUTE ON FUNCTIONS TO service_role;

-- Crear el role webscraper si no existe
-- NOTA: La contraseña debe configurarse usando variable de entorno WEBSCRAPER_PASSWORD
-- o mediante script post-migración por seguridad
DO $$
DECLARE
    WEBSCRAPER_PASSWORD TEXT;
BEGIN
    -- Verificar si el rol existe, si no existe crearlo
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'webscraper') THEN
        -- Intentar obtener contraseña de variable de entorno
        WEBSCRAPER_PASSWORD := current_setting('webscraper.password', true);
        
        IF WEBSCRAPER_PASSWORD IS NULL OR WEBSCRAPER_PASSWORD = '' THEN
            -- Crear rol sin contraseña, debe configurarse posteriormente
            CREATE ROLE webscraper LOGIN;
            RAISE NOTICE 'Rol webscraper creado SIN CONTRASEÑA. Configure la contraseña con: ALTER USER webscraper PASSWORD ''su_contraseña'';';
        ELSE
            -- Usar contraseña de variable de entorno
            EXECUTE format('CREATE ROLE webscraper LOGIN PASSWORD %L', WEBSCRAPER_PASSWORD);
            RAISE NOTICE 'Rol webscraper creado con contraseña desde variable de entorno';
        END IF;
    ELSE
        RAISE NOTICE 'Rol webscraper ya existe, continuamos...';
    END IF;
END;
$$;

-- Dar permisos a webscraper
GRANT USAGE ON SCHEMA webscraping TO webscraper;

ALTER DEFAULT PRIVILEGES IN SCHEMA webscraping
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO webscraper;

ALTER DEFAULT PRIVILEGES IN SCHEMA webscraping
GRANT USAGE, SELECT ON SEQUENCES TO webscraper;

ALTER DEFAULT PRIVILEGES IN SCHEMA webscraping
GRANT EXECUTE ON FUNCTIONS TO webscraper;

-- Habilitar extensiones necesarias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- TABLA: alembic_version
-- Descripción: Tabla de control de versiones de Alembic (requerida para el sistema de migraciones).
-- ============================================================================
CREATE TABLE webscraping.alembic_version (
    version_num VARCHAR(32) NOT NULL,
    CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num)
);

-- ============================================================================
-- TABLA: technology_templates
-- Templates reutilizables para configuraciones de CMS/plataformas (WordPress, Drupal, etc.)
-- IMPORTANTE: Esta tabla debe crearse ANTES que parsing_rules (foreign key dependency)
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.technology_templates (
    id SERIAL PRIMARY KEY,
    technology_type VARCHAR(50) NOT NULL,
    template_name VARCHAR(100) NOT NULL,
    version VARCHAR(20) NOT NULL DEFAULT '1.0',
    description TEXT,
    
    -- Configuraciones como JSONB
    discovery_config JSONB NOT NULL DEFAULT '{}'::jsonb,
    parsing_config JSONB NOT NULL DEFAULT '{}'::jsonb,
    normalization_config JSONB NOT NULL DEFAULT '{}'::jsonb,
    sitemap_discovery_config JSONB DEFAULT NULL,
    
    -- Metadata
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_by VARCHAR(100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Unique constraint
    CONSTRAINT uq_technology_templates_type_name UNIQUE (technology_type, template_name)
);

-- Índices requeridos para technology_templates
CREATE INDEX IF NOT EXISTS idx_technology_templates_type 
ON webscraping.technology_templates(technology_type);

CREATE INDEX IF NOT EXISTS idx_technology_templates_active 
ON webscraping.technology_templates(is_active) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_technology_templates_discovery 
ON webscraping.technology_templates USING gin(discovery_config);

CREATE INDEX IF NOT EXISTS idx_technology_templates_parsing 
ON webscraping.technology_templates USING gin(parsing_config);

-- ============================================================================
-- TABLA: source_statuses
-- Catálogo de estados posibles para sources
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.source_statuses (
    code VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT NOT NULL,
    color VARCHAR(20) NOT NULL,
    can_be_set_manually BOOLEAN DEFAULT false,
    requires_reason BOOLEAN DEFAULT false,
    display_order INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE webscraping.source_statuses IS 'Catálogo de estados posibles para sources';
COMMENT ON COLUMN webscraping.source_statuses.code IS 'Código único del estado (pending, active, error, disabled)';
COMMENT ON COLUMN webscraping.source_statuses.can_be_set_manually IS 'Indica si un usuario puede establecer este estado manualmente';
COMMENT ON COLUMN webscraping.source_statuses.requires_reason IS 'Indica si este estado requiere una razón al ser establecido';

-- Insertar estados iniciales
INSERT INTO webscraping.source_statuses (code, name, description, color, can_be_set_manually, requires_reason, display_order) VALUES
('pending', 'Pendiente', 'Esperando validación inicial de robots.txt', 'yellow', false, false, 1),
('active', 'Activo', 'Funcionando correctamente y disponible para crawling', 'green', false, false, 2),
('error', 'Error', 'Fallo automático detectado. Requiere revisión técnica antes de reactivar.', 'red', false, false, 3),
('disabled', 'Desactivado', 'Desactivado manualmente por un administrador', 'gray', true, true, 4);

-- ============================================================================
-- TABLA: source_status_transitions
-- Define las transiciones de estado permitidas
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.source_status_transitions (
    id SERIAL PRIMARY KEY,
    from_status VARCHAR(50) REFERENCES webscraping.source_statuses(code),
    to_status VARCHAR(50) NOT NULL REFERENCES webscraping.source_statuses(code),
    requires_permission VARCHAR(100),
    is_automatic BOOLEAN DEFAULT false,
    description TEXT,
    UNIQUE(from_status, to_status)
);

COMMENT ON TABLE webscraping.source_status_transitions IS 'Define las transiciones de estado permitidas para sources';
COMMENT ON COLUMN webscraping.source_status_transitions.from_status IS 'Estado de origen (NULL para creación inicial)';
COMMENT ON COLUMN webscraping.source_status_transitions.requires_permission IS 'Permiso requerido para realizar esta transición manualmente';
COMMENT ON COLUMN webscraping.source_status_transitions.is_automatic IS 'Indica si esta transición puede ocurrir automáticamente';

-- Insertar transiciones permitidas
INSERT INTO webscraping.source_status_transitions (from_status, to_status, requires_permission, is_automatic, description) VALUES
-- Desde pending
('pending', 'active', NULL, true, 'Validación automática exitosa'),
('pending', 'error', NULL, true, 'Fallo en validación automática'),
('pending', 'disabled', 'webscraping.edit', false, 'Desactivación manual antes de validar'),

-- Desde active
('active', 'error', NULL, true, 'Fallo detectado durante operación'),
('active', 'disabled', 'webscraping.edit', false, 'Desactivación manual'),

-- Desde error (requiere permiso especial)
('error', 'pending', 'webscraping.manage_errors', false, 'Reintentar validación después de correcciones técnicas'),
('error', 'disabled', 'webscraping.edit', false, 'Desactivación permanente'),

-- Desde disabled
('disabled', 'pending', 'webscraping.edit', false, 'Reactivación para re-validar'),
('disabled', 'active', 'webscraping.edit', false, 'Reactivación directa (si ya fue validado antes)');

-- ============================================================================
-- TABLA: sources
-- Tabla principal de fuentes de datos - Información estática
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.sources (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    base_url VARCHAR(500) NOT NULL UNIQUE,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    technology_template_id INTEGER,
    last_error_message TEXT,
    last_error_code VARCHAR(100),
    last_api_call_id BIGINT,
    last_error_at TIMESTAMPTZ,
    disabled_by UUID,
    disabled_at TIMESTAMPTZ,
    disabled_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_sources_status FOREIGN KEY (status) REFERENCES webscraping.source_statuses(code),
    CONSTRAINT fk_sources_template FOREIGN KEY (technology_template_id) REFERENCES webscraping.technology_templates(id) ON DELETE SET NULL,
    CONSTRAINT check_disabled_fields CHECK (
        (status = 'disabled' AND disabled_reason IS NOT NULL AND disabled_by IS NOT NULL AND disabled_at IS NOT NULL)
        OR status != 'disabled'
    )
);

-- Índices requeridos para sources
CREATE UNIQUE INDEX IF NOT EXISTS idx_sources_base_url ON webscraping.sources(base_url);
CREATE INDEX IF NOT EXISTS idx_sources_status ON webscraping.sources(status);
CREATE INDEX IF NOT EXISTS idx_sources_template ON webscraping.sources(technology_template_id);
CREATE INDEX IF NOT EXISTS idx_sources_last_error ON webscraping.sources(last_error_at DESC NULLS LAST) WHERE last_error_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sources_disabled_by ON webscraping.sources(disabled_by) WHERE disabled_by IS NOT NULL;

-- Comentarios
COMMENT ON TABLE webscraping.sources IS 'Tabla principal de fuentes de datos - Información estática';
COMMENT ON COLUMN webscraping.sources.base_url IS 'URL base del sitio web (única)';
COMMENT ON COLUMN webscraping.sources.status IS 'Estado de la fuente: pending, active, error, disabled';
COMMENT ON COLUMN webscraping.sources.last_error_message IS 'Último mensaje de error al llamar a la API externa';
COMMENT ON COLUMN webscraping.sources.last_error_code IS 'Último código de error al llamar a la API externa';
COMMENT ON COLUMN webscraping.sources.last_api_call_id IS 'Referencia al último registro de auditoría de llamada a API externa';
COMMENT ON COLUMN webscraping.sources.last_error_at IS 'Fecha y hora del último error registrado';
COMMENT ON COLUMN webscraping.sources.disabled_by IS 'Usuario que desactivó el source (NULL si no está desactivado)';
COMMENT ON COLUMN webscraping.sources.disabled_at IS 'Fecha y hora de desactivación manual';
COMMENT ON COLUMN webscraping.sources.disabled_reason IS 'Razón de desactivación (obligatorio cuando status=disabled)';

-- ============================================================================
-- TABLA: source_status_history
-- Histórico de cambios de estado para auditoría completa
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.source_status_history (
    id BIGSERIAL PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES webscraping.sources(id) ON DELETE CASCADE,
    from_status VARCHAR(50) REFERENCES webscraping.source_statuses(code),
    to_status VARCHAR(50) NOT NULL REFERENCES webscraping.source_statuses(code),
    changed_by UUID,
    reason TEXT,
    api_call_id BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_source_status_history_source_id ON webscraping.source_status_history(source_id);
CREATE INDEX idx_source_status_history_created_at ON webscraping.source_status_history(created_at DESC);
CREATE INDEX idx_source_status_history_changed_by ON webscraping.source_status_history(changed_by) WHERE changed_by IS NOT NULL;

COMMENT ON TABLE webscraping.source_status_history IS 'Histórico de cambios de estado para sources - auditoría completa';
COMMENT ON COLUMN webscraping.source_status_history.from_status IS 'Estado anterior (NULL en creación inicial)';
COMMENT ON COLUMN webscraping.source_status_history.to_status IS 'Nuevo estado';
COMMENT ON COLUMN webscraping.source_status_history.changed_by IS 'Usuario que realizó el cambio (NULL si fue automático)';
COMMENT ON COLUMN webscraping.source_status_history.reason IS 'Razón del cambio de estado (obligatorio para status=disabled)';
COMMENT ON COLUMN webscraping.source_status_history.api_call_id IS 'Referencia a audit.api_calls si el cambio fue por llamada API externa';

-- ============================================================================
-- TABLA: source_info
-- Información dinámica de robots.txt para cada fuente
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.source_info (
    id SERIAL PRIMARY KEY,
    source_id INTEGER NOT NULL UNIQUE REFERENCES webscraping.sources(id) ON DELETE CASCADE,
    robots_allowed BOOLEAN NOT NULL DEFAULT true,
    robots_raw TEXT, -- Contenido completo del fichero robots.txt
    sitemap_index_url VARCHAR(500),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índices requeridos para source_info
CREATE UNIQUE INDEX IF NOT EXISTS idx_source_info_source_id ON webscraping.source_info(source_id);
CREATE INDEX IF NOT EXISTS idx_source_info_updated_at ON webscraping.source_info(updated_at);

-- Comentarios
COMMENT ON TABLE webscraping.source_info IS 'Información dinámica de robots.txt para cada fuente (se actualiza cuando se re-consulta robots.txt)';
COMMENT ON COLUMN webscraping.source_info.robots_raw IS 'Contenido completo del fichero robots.txt';

-- ============================================================================
-- TABLA: venues
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.venues (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    address VARCHAR(500),
    city VARCHAR(100),
    postal_code VARCHAR(20),
    region VARCHAR(100),
    country VARCHAR(2) NOT NULL DEFAULT 'ES',
    google_maps_url VARCHAR(1000),
    lat FLOAT,
    lon FLOAT,
    geohash VARCHAR(12),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índices requeridos para venues
CREATE INDEX IF NOT EXISTS idx_venues_name ON webscraping.venues(name);
CREATE INDEX IF NOT EXISTS idx_venues_city ON webscraping.venues(city);
CREATE INDEX IF NOT EXISTS idx_venues_geohash ON webscraping.venues USING hash(geohash) WHERE geohash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_venues_location ON webscraping.venues(lat, lon) WHERE lat IS NOT NULL AND lon IS NOT NULL;

-- ============================================================================
-- TABLA: organizers
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.organizers (
    id SERIAL PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES webscraping.sources(id) ON DELETE CASCADE,
    name VARCHAR(500) NOT NULL,
    display_name VARCHAR(500),
    slug VARCHAR(500) NOT NULL,
    url VARCHAR(2000) NOT NULL,
    address VARCHAR(500),
    city VARCHAR(200),
    region VARCHAR(200),
    country VARCHAR(100),
    latitude FLOAT,
    longitude FLOAT,
    geohash VARCHAR(12),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_id, slug)
);

-- Índices requeridos para organizers
CREATE UNIQUE INDEX IF NOT EXISTS uq_organizers_source_slug ON webscraping.organizers(source_id, slug);
CREATE INDEX IF NOT EXISTS idx_organizers_source_id ON webscraping.organizers(source_id);
CREATE INDEX IF NOT EXISTS idx_organizers_geohash ON webscraping.organizers USING hash(geohash) WHERE geohash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_organizers_name ON webscraping.organizers(name);

-- ============================================================================
-- TABLA: event_categories
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.event_categories (
    id SERIAL PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES webscraping.sources(id) ON DELETE CASCADE,
    name VARCHAR(500) NOT NULL,
    slug VARCHAR(500) NOT NULL,
    url VARCHAR(2000) NOT NULL,
    app_category_key VARCHAR(100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_id, slug)
);

-- Índices requeridos para event_categories
CREATE UNIQUE INDEX IF NOT EXISTS uq_event_categories_source_slug ON webscraping.event_categories(source_id, slug);
CREATE INDEX IF NOT EXISTS idx_event_categories_source_id ON webscraping.event_categories(source_id);
CREATE INDEX IF NOT EXISTS idx_event_categories_name ON webscraping.event_categories(name);
CREATE INDEX IF NOT EXISTS idx_event_categories_slug ON webscraping.event_categories(slug);

-- ============================================================================
-- TABLA: age_groups
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.age_groups (
    id SERIAL PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES webscraping.sources(id) ON DELETE CASCADE,
    name VARCHAR(500) NOT NULL,
    display_name VARCHAR(500),
    slug VARCHAR(500) NOT NULL,
    url VARCHAR(2000) NOT NULL,
    min_age INTEGER,
    max_age INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_id, slug)
);

-- Índices requeridos para age_groups
CREATE UNIQUE INDEX IF NOT EXISTS uq_age_groups_source_slug ON webscraping.age_groups(source_id, slug);
CREATE INDEX IF NOT EXISTS idx_age_groups_source_id ON webscraping.age_groups(source_id);
CREATE INDEX IF NOT EXISTS idx_age_groups_age_range ON webscraping.age_groups(min_age, max_age) WHERE min_age IS NOT NULL;

-- ============================================================================
-- TABLA: pages
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.pages (
    id SERIAL PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES webscraping.sources(id) ON DELETE CASCADE,
    url VARCHAR(2000) NOT NULL,
    url_norm VARCHAR(2000) NOT NULL,
    url_hash VARCHAR(64) NOT NULL,
    lastmod VARCHAR(50),
    etag VARCHAR(200),
    last_modified TIMESTAMPTZ,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    http_status INTEGER,
    content_hash VARCHAR(64),
    last_crawled_at TIMESTAMPTZ,
    next_crawl_at TIMESTAMPTZ,
    fail_count INTEGER NOT NULL DEFAULT 0,
    discovered_by VARCHAR(50),
    UNIQUE (source_id, url_hash)
);

-- Crear índices para pages (CRÍTICOS para performance)
CREATE UNIQUE INDEX IF NOT EXISTS uq_pages_source_url_hash ON webscraping.pages(source_id, url_hash);
CREATE INDEX IF NOT EXISTS idx_pages_status_next_crawl ON webscraping.pages(status, next_crawl_at); -- Query principal del worker
CREATE INDEX IF NOT EXISTS idx_pages_source_status ON webscraping.pages(source_id, status);
CREATE INDEX IF NOT EXISTS idx_pages_url_hash ON webscraping.pages(url_hash);

-- ============================================================================
-- TABLA: source_configs
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.source_configs (
    source_key VARCHAR(100) PRIMARY KEY,
    config TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- COMENTARIOS PARA DOCUMENTACIÓN
-- ============================================================================
COMMENT ON SCHEMA webscraping IS 'Schema para datos de webscraping de eventos y contenido';
-- Comentario movido arriba con la definición de tabla
COMMENT ON TABLE webscraping.venues IS 'Lugares donde se celebran eventos';
COMMENT ON TABLE webscraping.organizers IS 'Organizadores de eventos';
COMMENT ON TABLE webscraping.event_categories IS 'Categorías de eventos';
COMMENT ON TABLE webscraping.age_groups IS 'Grupos de edad para eventos';
COMMENT ON TABLE webscraping.pages IS 'URLs rastreadas y su estado';
COMMENT ON TABLE webscraping.source_configs IS 'Configuraciones específicas por fuente';

-- ============================================================================
-- TABLA: source_configurations
-- Configuraciones específicas por sitio vinculadas a templates tecnológicos
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.source_configurations (
    id SERIAL PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES webscraping.sources(id) ON DELETE CASCADE,
    technology_template_id INTEGER REFERENCES webscraping.technology_templates(id) ON DELETE SET NULL,
    
    -- Configuraciones específicas del sitio (3 JSONB separados para mejor organización)
    overrides_config JSONB NOT NULL DEFAULT '{}'::jsonb,      -- Overrides de parsing/discovery
    politeness_config JSONB NOT NULL DEFAULT '{}'::jsonb,     -- Rate limiting, concurrency
    recrawl_config JSONB NOT NULL DEFAULT '{}'::jsonb,        -- Intervalos de recrawl
    
    -- Version control para rollback
    version INTEGER NOT NULL DEFAULT 1,
    parent_version_id INTEGER REFERENCES webscraping.source_configurations(id) ON DELETE SET NULL,
    
    -- Metadata
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_by VARCHAR(100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Unique constraint para version control
    CONSTRAINT uq_source_configurations_source_version UNIQUE (source_id, version)
);

-- Índices requeridos para source_configurations
CREATE INDEX IF NOT EXISTS idx_source_configurations_source 
ON webscraping.source_configurations(source_id);

CREATE INDEX IF NOT EXISTS idx_source_configurations_template 
ON webscraping.source_configurations(technology_template_id);

CREATE INDEX IF NOT EXISTS idx_source_configurations_active 
ON webscraping.source_configurations(source_id, is_active) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_source_configurations_version 
ON webscraping.source_configurations(source_id, version DESC);

CREATE INDEX IF NOT EXISTS idx_source_configurations_overrides 
ON webscraping.source_configurations USING gin(overrides_config);

CREATE INDEX IF NOT EXISTS idx_source_configurations_politeness 
ON webscraping.source_configurations USING gin(politeness_config);

CREATE INDEX IF NOT EXISTS idx_source_configurations_recrawl 
ON webscraping.source_configurations USING gin(recrawl_config);

-- ============================================================================
-- TABLA: sitemap_discovery
-- Sitemaps descubiertos con análisis de estructura y estado de selección
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.sitemap_discovery (
    id SERIAL PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES webscraping.sources(id) ON DELETE CASCADE,
    
    -- Información del sitemap
    sitemap_url VARCHAR(2000) NOT NULL,
    sitemap_url_hash VARCHAR(64) NOT NULL,
    parent_sitemap_id INTEGER REFERENCES webscraping.sitemap_discovery(id) ON DELETE CASCADE,
    
    -- Clasificación automática
    sitemap_type VARCHAR(50),        -- index, events, venues, posts, categories, etc.
    content_type VARCHAR(50),        -- events, venues, organizers, posts, categories, age_groups
    
    -- Análisis de estructura
    structure_analysis JSONB DEFAULT NULL,
    
    -- Estadísticas
    url_count INTEGER DEFAULT 0,
    last_analyzed_at TIMESTAMPTZ,
    
    -- Selección y filtrado
    is_selected BOOLEAN NOT NULL DEFAULT false,
    temporal_filter_config JSONB DEFAULT NULL,
    
    -- Metadata
    discovered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Unique constraint
    CONSTRAINT uq_sitemap_discovery_source_hash UNIQUE (source_id, sitemap_url_hash)
);

-- Índices requeridos para sitemap_discovery
CREATE INDEX IF NOT EXISTS idx_sitemap_discovery_source 
ON webscraping.sitemap_discovery(source_id);

CREATE INDEX IF NOT EXISTS idx_sitemap_discovery_type 
ON webscraping.sitemap_discovery(source_id, sitemap_type);

CREATE INDEX IF NOT EXISTS idx_sitemap_discovery_content_type 
ON webscraping.sitemap_discovery(source_id, content_type);

CREATE INDEX IF NOT EXISTS idx_sitemap_discovery_selected 
ON webscraping.sitemap_discovery(source_id, is_selected) WHERE is_selected = true;

CREATE INDEX IF NOT EXISTS idx_sitemap_discovery_parent 
ON webscraping.sitemap_discovery(parent_sitemap_id) WHERE parent_sitemap_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sitemap_discovery_structure 
ON webscraping.sitemap_discovery USING gin(structure_analysis);

-- ============================================================================
-- COMENTARIOS ADICIONALES PARA NUEVAS TABLAS
-- ============================================================================
COMMENT ON TABLE webscraping.technology_templates IS 'Templates reutilizables para configuraciones de CMS/plataformas (WordPress, Drupal, etc.)';
COMMENT ON TABLE webscraping.source_configurations IS 'Configuraciones específicas por sitio vinculadas a templates tecnológicos';
COMMENT ON TABLE webscraping.sitemap_discovery IS 'Sitemaps descubiertos con análisis de estructura y estado de selección';

-- ============================================================================
-- TRIGGERS PARA UPDATED_AT
-- ============================================================================
CREATE OR REPLACE FUNCTION webscraping.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Aplicar trigger a tablas que tienen updated_at
CREATE TRIGGER update_organizers_updated_at 
    BEFORE UPDATE ON webscraping.organizers 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

CREATE TRIGGER update_event_categories_updated_at 
    BEFORE UPDATE ON webscraping.event_categories 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

CREATE TRIGGER update_age_groups_updated_at 
    BEFORE UPDATE ON webscraping.age_groups 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

CREATE TRIGGER update_source_configs_updated_at 
    BEFORE UPDATE ON webscraping.source_configs 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

-- Trigger para technology_templates
CREATE TRIGGER update_technology_templates_updated_at 
    BEFORE UPDATE ON webscraping.technology_templates 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

-- Trigger para source_configurations
CREATE TRIGGER update_source_configurations_updated_at 
    BEFORE UPDATE ON webscraping.source_configurations 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

-- Trigger para sitemap_discovery
CREATE TRIGGER update_sitemap_discovery_updated_at 
    BEFORE UPDATE ON webscraping.sitemap_discovery 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

-- ============================================================================
-- TRIGGER PARA source_info
-- ============================================================================
-- Trigger para actualizar updated_at en source_info
CREATE TRIGGER update_source_info_updated_at 
    BEFORE UPDATE ON webscraping.source_info 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

-- ============================================================================
-- VISTA DE COMPATIBILIDAD
-- ============================================================================
-- Vista que combina sources + source_info para facilitar consultas
CREATE OR REPLACE VIEW webscraping.sources_with_info AS
SELECT 
    s.id,
    s.name,
    s.base_url,
    s.status,
    s.technology_template_id,
    tt.id as template_id,
    tt.template_name,
    s.created_at,
    s.last_error_message,
    s.last_error_code,
    s.last_api_call_id,
    s.last_error_at,
    s.disabled_by,
    s.disabled_at,
    s.disabled_reason,
    si.robots_allowed,
    si.robots_raw,
    si.sitemap_index_url,
    si.updated_at as info_updated_at
FROM webscraping.sources s
LEFT JOIN webscraping.source_info si ON s.id = si.source_id
LEFT JOIN webscraping.technology_templates tt ON s.technology_template_id = tt.id;

COMMENT ON VIEW webscraping.sources_with_info IS 'Vista que combina sources + source_info + technology_templates para facilitar consultas';

-- ============================================================================
-- NOTA IMPORTANTE SOBRE PERMISOS
-- ============================================================================
-- Los permisos para todas las tablas, sequences y funciones están configurados
-- mediante ALTER DEFAULT PRIVILEGES al inicio de esta migración.
-- Todos los objetos creados DESPUÉS de esa configuración ya tienen los permisos
-- automáticamente aplicados para service_role y webscraper.
-- ============================================================================