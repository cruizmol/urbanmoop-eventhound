-- ============================================================================
-- MIGRACIÓN 002: Crear Tablas de Contenido (Events, Posts, Related Links)
-- Fecha: 2025-11-27
-- Descripción: Crea las tablas principales de contenido
-- Dependencias: 001_create_schema_and_basic_tables.sql
-- ============================================================================

-- ============================================================================
-- TABLA: events
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.events (
    id SERIAL PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES webscraping.sources(id) ON DELETE CASCADE,
    page_id INTEGER NOT NULL REFERENCES webscraping.pages(id) ON DELETE CASCADE,
    title VARCHAR(500),
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    tz VARCHAR(50),
    category VARCHAR(100),
    language VARCHAR(10) NOT NULL DEFAULT 'ca',
    description TEXT,
    recommended_ages VARCHAR(100),
    price_amount VARCHAR(50),
    price_currency VARCHAR(10),
    price_type VARCHAR(50),
    price_text VARCHAR(500),
    registration_url VARCHAR(2000),
    content_hash VARCHAR(64),
    venue_id INTEGER REFERENCES webscraping.venues(id) ON DELETE SET NULL,
    organizer_id INTEGER REFERENCES webscraping.organizers(id) ON DELETE SET NULL,
    category_id INTEGER REFERENCES webscraping.event_categories(id) ON DELETE SET NULL,
    age_group_id INTEGER REFERENCES webscraping.age_groups(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índices para events
CREATE INDEX IF NOT EXISTS idx_events_starts_at ON webscraping.events(starts_at);
CREATE INDEX IF NOT EXISTS idx_events_source_starts_at ON webscraping.events(source_id, starts_at) WHERE starts_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_events_time_range ON webscraping.events(starts_at, ends_at) WHERE starts_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_events_venue_id ON webscraping.events(venue_id) WHERE venue_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_events_organizer_id ON webscraping.events(organizer_id) WHERE organizer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_events_category_id ON webscraping.events(category_id) WHERE category_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_events_age_group_id ON webscraping.events(age_group_id) WHERE age_group_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_events_content_hash ON webscraping.events(content_hash) WHERE content_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_events_language ON webscraping.events(language);

-- ============================================================================
-- TABLA: posts
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.posts (
    id SERIAL PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES webscraping.sources(id) ON DELETE CASCADE,
    page_id INTEGER NOT NULL REFERENCES webscraping.pages(id) ON DELETE CASCADE,
    title VARCHAR(500) NOT NULL,
    content TEXT NOT NULL,
    excerpt TEXT,
    published_at TIMESTAMPTZ,
    language VARCHAR(10) NOT NULL DEFAULT 'ca',
    image_url VARCHAR(2000),
    content_hash VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índices para posts
CREATE INDEX IF NOT EXISTS idx_posts_published_at ON webscraping.posts(published_at);
CREATE INDEX IF NOT EXISTS idx_posts_source_published ON webscraping.posts(source_id, published_at) WHERE published_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_posts_content_hash ON webscraping.posts(content_hash) WHERE content_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_posts_language ON webscraping.posts(language);

-- ============================================================================
-- TABLA: post_categories (many-to-many)
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.post_categories (
    post_id INTEGER NOT NULL REFERENCES webscraping.posts(id) ON DELETE CASCADE,
    category_id INTEGER NOT NULL REFERENCES webscraping.event_categories(id) ON DELETE CASCADE,
    PRIMARY KEY (post_id, category_id)
);

-- ============================================================================
-- TABLA: related_links
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.related_links (
    id SERIAL PRIMARY KEY,
    source_id INTEGER NOT NULL REFERENCES webscraping.sources(id) ON DELETE CASCADE,
    from_page_id INTEGER NOT NULL REFERENCES webscraping.pages(id) ON DELETE CASCADE,
    to_url VARCHAR(2000) NOT NULL,
    to_url_norm VARCHAR(2000) NOT NULL,
    to_url_hash VARCHAR(64) NOT NULL,
    link_type VARCHAR(50),
    discovered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_id, to_url_hash)
);

-- Índices para related_links
CREATE UNIQUE INDEX IF NOT EXISTS uq_related_links_source_url_hash ON webscraping.related_links(source_id, to_url_hash);
CREATE INDEX IF NOT EXISTS idx_related_links_source_discovered ON webscraping.related_links(source_id, discovered_at);

-- ============================================================================
-- TRIGGERS PARA UPDATED_AT
-- ============================================================================

-- Trigger para events
CREATE TRIGGER update_events_updated_at 
    BEFORE UPDATE ON webscraping.events 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

-- Trigger para posts
CREATE TRIGGER update_posts_updated_at 
    BEFORE UPDATE ON webscraping.posts 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

-- ============================================================================
-- COMENTARIOS PARA DOCUMENTACIÓN
-- ============================================================================
COMMENT ON TABLE webscraping.events IS 'Eventos extraídos del webscraping';
COMMENT ON TABLE webscraping.posts IS 'Posts/artículos extraídos del webscraping';
COMMENT ON TABLE webscraping.post_categories IS 'Relación many-to-many entre posts y categorías';
COMMENT ON TABLE webscraping.related_links IS 'Enlaces relacionados descubiertos durante el crawling';

COMMENT ON COLUMN webscraping.events.price_type IS 'Tipo de precio: free, paid, donation, variable';
COMMENT ON COLUMN webscraping.events.language IS 'Código de idioma ISO 639-1';
COMMENT ON COLUMN webscraping.events.content_hash IS 'Hash del contenido para detectar cambios';
COMMENT ON COLUMN webscraping.posts.language IS 'Código de idioma ISO 639-1';
COMMENT ON COLUMN webscraping.related_links.link_type IS 'Tipo de enlace: internal, external, event, etc.';

-- Nota: Los permisos para sequences y tablas son otorgados automáticamente
-- por ALTER DEFAULT PRIVILEGES configurado en 001_create_schema_and_basic_tables.sql