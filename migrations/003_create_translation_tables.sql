-- ============================================================================
-- MIGRACIÓN 003: Crear Tablas de Traducción Multilingüe
-- Fecha: 2025-11-27
-- Descripción: Crea las tablas de traducción para soporte multilingüe
-- Dependencias: 002_create_content_tables.sql
-- ============================================================================

-- ============================================================================
-- TABLA: event_translations
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.event_translations (
    id SERIAL PRIMARY KEY,
    event_id INTEGER NOT NULL REFERENCES webscraping.events(id) ON DELETE CASCADE,
    language VARCHAR(10) NOT NULL,
    title VARCHAR(500),
    description TEXT,
    price_text VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (event_id, language)
);

-- Índices para event_translations
CREATE INDEX IF NOT EXISTS idx_event_translations_language ON webscraping.event_translations(language);

-- ============================================================================
-- TABLA: post_translations
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.post_translations (
    id SERIAL PRIMARY KEY,
    post_id INTEGER NOT NULL REFERENCES webscraping.posts(id) ON DELETE CASCADE,
    language VARCHAR(10) NOT NULL,
    title VARCHAR(500),
    content TEXT,
    excerpt TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (post_id, language)
);

-- Índices para post_translations
CREATE INDEX IF NOT EXISTS idx_post_translations_language ON webscraping.post_translations(language);

-- ============================================================================
-- TABLA: venue_translations
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.venue_translations (
    id SERIAL PRIMARY KEY,
    venue_id INTEGER NOT NULL REFERENCES webscraping.venues(id) ON DELETE CASCADE,
    language VARCHAR(10) NOT NULL,
    name VARCHAR(200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (venue_id, language)
);

-- Índices para venue_translations
CREATE INDEX IF NOT EXISTS idx_venue_translations_language ON webscraping.venue_translations(language);

-- ============================================================================
-- TABLA: organizer_translations
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.organizer_translations (
    id SERIAL PRIMARY KEY,
    organizer_id INTEGER NOT NULL REFERENCES webscraping.organizers(id) ON DELETE CASCADE,
    language VARCHAR(10) NOT NULL,
    display_name VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (organizer_id, language)
);

-- Índices para organizer_translations
CREATE INDEX IF NOT EXISTS idx_organizer_translations_language ON webscraping.organizer_translations(language);

-- ============================================================================
-- TABLA: event_category_translations
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.event_category_translations (
    id SERIAL PRIMARY KEY,
    category_id INTEGER NOT NULL REFERENCES webscraping.event_categories(id) ON DELETE CASCADE,
    language VARCHAR(10) NOT NULL,
    name VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (category_id, language)
);

-- Índices para event_category_translations
CREATE INDEX IF NOT EXISTS idx_event_category_translations_language ON webscraping.event_category_translations(language);

-- ============================================================================
-- TABLA: age_group_translations
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.age_group_translations (
    id SERIAL PRIMARY KEY,
    age_group_id INTEGER NOT NULL REFERENCES webscraping.age_groups(id) ON DELETE CASCADE,
    language VARCHAR(10) NOT NULL,
    display_name VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (age_group_id, language)
);

-- Índices para age_group_translations
CREATE INDEX IF NOT EXISTS idx_age_group_translations_language ON webscraping.age_group_translations(language);

-- ============================================================================
-- TRIGGERS PARA UPDATED_AT
-- ============================================================================

-- Triggers para todas las tablas de traducción
CREATE TRIGGER update_event_translations_updated_at 
    BEFORE UPDATE ON webscraping.event_translations 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

CREATE TRIGGER update_post_translations_updated_at 
    BEFORE UPDATE ON webscraping.post_translations 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

CREATE TRIGGER update_venue_translations_updated_at 
    BEFORE UPDATE ON webscraping.venue_translations 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

CREATE TRIGGER update_organizer_translations_updated_at 
    BEFORE UPDATE ON webscraping.organizer_translations 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

CREATE TRIGGER update_event_category_translations_updated_at 
    BEFORE UPDATE ON webscraping.event_category_translations 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

CREATE TRIGGER update_age_group_translations_updated_at 
    BEFORE UPDATE ON webscraping.age_group_translations 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

-- ============================================================================
-- COMENTARIOS PARA DOCUMENTACIÓN
-- ============================================================================
COMMENT ON TABLE webscraping.event_translations IS 'Traducciones de eventos para soporte multilingüe';
COMMENT ON TABLE webscraping.post_translations IS 'Traducciones de posts para soporte multilingüe';
COMMENT ON TABLE webscraping.venue_translations IS 'Traducciones de venues para soporte multilingüe';
COMMENT ON TABLE webscraping.organizer_translations IS 'Traducciones de organizadores para soporte multilingüe';
COMMENT ON TABLE webscraping.event_category_translations IS 'Traducciones de categorías para soporte multilingüe';
COMMENT ON TABLE webscraping.age_group_translations IS 'Traducciones de grupos de edad para soporte multilingüe';

-- ============================================================================
-- FUNCIÓN HELPER PARA OBTENER TRADUCCIÓN
-- ============================================================================
CREATE OR REPLACE FUNCTION webscraping.get_translation(
    table_name TEXT,
    entity_id INTEGER,
    field_name TEXT,
    preferred_language VARCHAR(10) DEFAULT 'ca',
    fallback_language VARCHAR(10) DEFAULT 'es'
) RETURNS TEXT AS $$
DECLARE
    result TEXT;
    query_sql TEXT;
BEGIN
    -- Intentar obtener en el idioma preferido
    query_sql := format('SELECT %I FROM webscraping.%I WHERE %s_id = %s AND language = %L LIMIT 1',
                       field_name, table_name, 
                       CASE 
                           WHEN table_name LIKE '%event%' THEN 'event'
                           WHEN table_name LIKE '%post%' THEN 'post'
                           WHEN table_name LIKE '%venue%' THEN 'venue'
                           WHEN table_name LIKE '%organizer%' THEN 'organizer'
                           WHEN table_name LIKE '%category%' THEN 'category'
                           WHEN table_name LIKE '%age_group%' THEN 'age_group'
                           ELSE 'unknown'
                       END,
                       entity_id, preferred_language);
    
    EXECUTE query_sql INTO result;
    
    -- Si no se encontró, intentar con el idioma fallback
    IF result IS NULL AND fallback_language != preferred_language THEN
        query_sql := format('SELECT %I FROM webscraping.%I WHERE %s_id = %s AND language = %L LIMIT 1',
                           field_name, table_name,
                           CASE 
                               WHEN table_name LIKE '%event%' THEN 'event'
                               WHEN table_name LIKE '%post%' THEN 'post'
                               WHEN table_name LIKE '%venue%' THEN 'venue'
                               WHEN table_name LIKE '%organizer%' THEN 'organizer'
                               WHEN table_name LIKE '%category%' THEN 'category'
                               WHEN table_name LIKE '%age_group%' THEN 'age_group'
                               ELSE 'unknown'
                           END,
                           entity_id, fallback_language);
        
        EXECUTE query_sql INTO result;
    END IF;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Nota: Los permisos para sequences y tablas son otorgados automáticamente
-- por ALTER DEFAULT PRIVILEGES configurado en 001_create_schema_and_basic_tables.sql