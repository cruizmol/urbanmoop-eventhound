-- ============================================================================
-- MIGRACIÓN 005: Poblar Tablas con Datos Iniciales
-- Fecha: 2025-11-27
-- Descripción: Inserta datos iniciales y reglas de parsing por defecto
-- Dependencias: 004_create_parsing_rules.sql
-- ============================================================================

-- ============================================================================
-- DATOS INICIALES: REGLAS DE PARSING PARA GRUPOS DE EDAD
-- ============================================================================
INSERT INTO webscraping.parsing_rules (rule_type, entity_type, priority, pattern, config, description, is_active)
VALUES
-- Regla 1: Parseo de rangos "De X a Y anys/años"
(
    'age_range_parser',
    'age_group',
    10,
    'De (\d+) a (\d+) (anys|años)',
    '{"extract": ["min_age", "max_age"], "match_strategy": "range_overlap", "tolerance": 0}'::jsonb,
    'Parsea rangos de edad en formato: De X a Y anys/años',
    true
),

-- Regla 2: Parseo de edad única "X anys/años"
(
    'age_single_parser',
    'age_group',
    20,
    '(\d+) (anys|años)',
    '{"extract": ["age"], "match_strategy": "exact_min", "tolerance": 1}'::jsonb,
    'Parsea edad única: X anys/años',
    true
),

-- Regla 3: Rangos con guion "X-Y anys"
(
    'age_range_hyphen_parser',
    'age_group',
    15,
    '(\d+)-(\d+) (anys|años)',
    '{"extract": ["min_age", "max_age"], "match_strategy": "range_overlap", "tolerance": 0}'::jsonb,
    'Parsea rangos con guion: X-Y anys',
    true
),

-- Regla 4: Todas las edades
(
    'age_all_parser',
    'age_group',
    30,
    '(Totes les edats|Todas las edades|All ages)',
    '{"match_strategy": "fallback", "fallback_slug": "totes-edats"}'::jsonb,
    'Detecta cuando es para todas las edades',
    true
),

-- Regla 5: Bebés (0-2 años)
(
    'age_baby_parser',
    'age_group',
    5,
    '(bebès|bebés|babies|nadons)',
    '{"extract": ["min_age", "max_age"], "min_age": 0, "max_age": 2, "match_strategy": "keyword"}'::jsonb,
    'Detecta referencias a bebés',
    true
),

-- Regla 6: Niños pequeños (3-5 años)
(
    'age_toddler_parser',
    'age_group',
    6,
    '(petits|pequeños|toddlers|preescolar)',
    '{"extract": ["min_age", "max_age"], "min_age": 3, "max_age": 5, "match_strategy": "keyword"}'::jsonb,
    'Detecta referencias a niños pequeños/preescolar',
    true
),

-- ============================================================================
-- DATOS INICIALES: REGLAS DE PARSING PARA PRECIOS
-- ============================================================================
-- Regla 7: Detectar entrada gratuita (multilingüe con catalán)
(
    'price_free_detector',
    'price',
    10,
    '(gratis|gratuït|gratuïta|gratuito|gratuita|free)',
    '{"match_strategy": "keyword", "result_value": "free"}'::jsonb,
    'Detecta cuando la entrada es gratuita (catalán, español, inglés)',
    true
),

-- Regla 8: Detectar donación voluntaria
(
    'price_donation_detector',
    'price',
    20,
    '(donació|donacion|donación|donation|voluntària|voluntaria|voluntary)',
    '{"match_strategy": "keyword", "result_value": "donation"}'::jsonb,
    'Detecta cuando es donación o aportación voluntaria',
    true
),

-- Regla 9: Detectar precio a consultar (variable)
(
    'price_variable_detector',
    'price',
    30,
    '(consultar|a determinar|variable|por confirmar|pendent)',
    '{"match_strategy": "keyword", "result_value": "variable"}'::jsonb,
    'Detecta cuando el precio está por determinar',
    true
),

-- Regla 10: Detectar precios en euros
(
    'price_euro_parser',
    'price',
    15,
    '(\d+(?:[.,]\d{2})?)[\s]*[€]',
    '{"extract": ["amount"], "currency": "EUR", "match_strategy": "regex"}'::jsonb,
    'Parsea precios en euros: 10€, 15.50€, etc.',
    true
),

-- ============================================================================
-- DATOS INICIALES: REGLAS DE PARSING PARA CATEGORÍAS
-- ============================================================================
-- Regla 11: Normalización de categorías de música
(
    'category_music_normalizer',
    'category',
    20,
    '(concert|concierto|concierto|música|musica|music)',
    '{"match_strategy": "keyword", "app_category_key": "music", "normalize_to": "música"}'::jsonb,
    'Normaliza categorías relacionadas con música',
    true
),

-- Regla 12: Normalización de categorías de teatro
(
    'category_theatre_normalizer',
    'category',
    21,
    '(teatre|teatro|theatre|theater|obra)',
    '{"match_strategy": "keyword", "app_category_key": "theatre", "normalize_to": "teatre"}'::jsonb,
    'Normaliza categorías relacionadas con teatro',
    true
),

-- Regla 13: Normalización de categorías infantiles
(
    'category_kids_normalizer',
    'category',
    22,
    '(infantil|familiar|kids|children|nens|niños)',
    '{"match_strategy": "keyword", "app_category_key": "family", "normalize_to": "familiar"}'::jsonb,
    'Normaliza categorías familiares/infantiles',
    true
),

-- ============================================================================
-- DATOS INICIALES: FUENTES DE EJEMPLO (OPCIONAL)
-- ============================================================================
-- Estas fuentes son ejemplos, puedes comentar esta sección si no las necesitas

INSERT INTO webscraping.sources (key, name, base_url, sitemap_index_url, robots_allowed, active)
VALUES 
(
    'exemple_bcn',
    'Ejemplo Barcelona Cultural',
    'https://ejemplo-barcelona.cat',
    'https://ejemplo-barcelona.cat/sitemap.xml',
    true,
    false  -- Inactivo por defecto, activar cuando esté configurado
),
(
    'exemple_cat',
    'Ejemplo Cultura Catalana',
    'https://ejemplo-cultura.cat',
    'https://ejemplo-cultura.cat/sitemap_index.xml',
    true,
    false  -- Inactivo por defecto
) ON CONFLICT (key) DO NOTHING; -- No fallar si ya existe

-- ============================================================================
-- DATOS INICIALES: CONFIGURACIONES DE EJEMPLO
-- ============================================================================
INSERT INTO webscraping.source_configs (source_key, config)
VALUES 
(
    'exemple_bcn',
    '{
        "parser_config": {
            "selectors": {
                "title": "h1.event-title, .title",
                "description": ".description, .content",
                "date": ".date, .event-date",
                "location": ".location, .venue",
                "price": ".price, .cost"
            },
            "date_formats": ["d/m/Y H:i", "Y-m-d H:i:s"],
            "default_language": "ca",
            "supported_languages": ["ca", "es", "en"]
        },
        "crawl_config": {
            "delay_between_requests": 1000,
            "max_concurrent_requests": 3,
            "respect_robots_txt": true,
            "user_agent": "UrbanMoop/1.0 (+https://urbanmoop.com)"
        }
    }'
),
(
    'exemple_cat',
    '{
        "parser_config": {
            "selectors": {
                "title": ".event-title",
                "description": ".event-description", 
                "date": ".event-datetime",
                "location": ".event-location",
                "price": ".event-price"
            },
            "date_formats": ["d-m-Y", "Y/m/d H:i"],
            "default_language": "ca"
        },
        "crawl_config": {
            "delay_between_requests": 2000,
            "max_concurrent_requests": 2
        }
    }'
) ON CONFLICT (source_key) DO UPDATE SET 
    config = EXCLUDED.config,
    updated_at = now();

-- ============================================================================
-- COMENTARIOS FINALES Y ESTADÍSTICAS
-- ============================================================================

-- Función para obtener estadísticas del schema
CREATE OR REPLACE FUNCTION webscraping.get_schema_stats()
RETURNS TABLE (
    table_name TEXT,
    row_count BIGINT,
    size_pretty TEXT
) AS $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN 
        SELECT schemaname, tablename 
        FROM pg_tables 
        WHERE schemaname = 'webscraping'
        ORDER BY tablename
    LOOP
        RETURN QUERY
        SELECT 
            rec.tablename::TEXT,
            (SELECT count(*) FROM pg_class WHERE relname = rec.tablename),
            pg_size_pretty(pg_total_relation_size('webscraping.' || rec.tablename))::TEXT;
    END LOOP;
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- Insertar log de migración completada
INSERT INTO webscraping.source_configs (source_key, config) 
VALUES (
    '_migration_log',
    format('{"migration_completed": "%s", "version": "005", "tables_created": %s}', 
           now()::text,
           (SELECT count(*) FROM pg_tables WHERE schemaname = 'webscraping'))
) ON CONFLICT (source_key) DO UPDATE SET 
    config = EXCLUDED.config,
    updated_at = now();

-- Mostrar resumen de la migración
DO $$
DECLARE
    table_count INTEGER;
    rule_count INTEGER;
    source_count INTEGER;
BEGIN
    SELECT count(*) INTO table_count FROM pg_tables WHERE schemaname = 'webscraping';
    SELECT count(*) INTO rule_count FROM webscraping.parsing_rules WHERE is_active = true;
    SELECT count(*) INTO source_count FROM webscraping.sources;
    
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'MIGRACIÓN WEBSCRAPING COMPLETADA EXITOSAMENTE';
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'Tablas creadas: %', table_count;
    RAISE NOTICE 'Reglas de parsing activas: %', rule_count;  
    RAISE NOTICE 'Fuentes configuradas: %', source_count;
    RAISE NOTICE 'Schema: webscraping';
    RAISE NOTICE 'Fecha: %', now();
    RAISE NOTICE '============================================================================';
END;
$$;