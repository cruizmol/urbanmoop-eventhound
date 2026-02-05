-- ============================================================================
-- MIGRACIÓN 004: Crear Tabla de Reglas de Parsing
-- Fecha: 2025-11-27
-- Descripción: Crea la tabla de reglas configurables para parsing
-- Dependencias: 003_create_translation_tables.sql
-- ============================================================================

-- Habilitar extensión para JSONB si no está habilitada
CREATE EXTENSION IF NOT EXISTS "btree_gin";

-- ============================================================================
-- TABLA: parsing_rules
-- ============================================================================
CREATE TABLE IF NOT EXISTS webscraping.parsing_rules (
    id SERIAL PRIMARY KEY,
    source_id INTEGER REFERENCES webscraping.sources(id) ON DELETE CASCADE, -- NULL = regla global
    
    -- Soporte de templates (vincula reglas a technology_templates)
    technology_template_id INTEGER REFERENCES webscraping.technology_templates(id) ON DELETE CASCADE,
    is_template_rule BOOLEAN NOT NULL DEFAULT false,
    applies_to_technology VARCHAR(50),
    
    -- Configuración de la regla
    rule_type VARCHAR(50) NOT NULL, -- regex, mapping, extraction
    entity_type VARCHAR(50) NOT NULL, -- age_group, price, category, organizer
    priority INTEGER NOT NULL DEFAULT 100,
    pattern TEXT,
    replacement TEXT,
    config JSONB,
    description VARCHAR(500),
    
    -- Metadata
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índices para parsing_rules
CREATE INDEX IF NOT EXISTS idx_parsing_rules_source_entity_active 
    ON webscraping.parsing_rules(source_id, entity_type, is_active);
CREATE INDEX IF NOT EXISTS idx_parsing_rules_priority 
    ON webscraping.parsing_rules(priority);
CREATE INDEX IF NOT EXISTS idx_parsing_rules_rule_type 
    ON webscraping.parsing_rules(rule_type);
CREATE INDEX IF NOT EXISTS idx_parsing_rules_config 
    ON webscraping.parsing_rules USING gin(config);
CREATE INDEX IF NOT EXISTS idx_parsing_rules_template 
    ON webscraping.parsing_rules(technology_template_id) WHERE technology_template_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_parsing_rules_is_template 
    ON webscraping.parsing_rules(is_template_rule, applies_to_technology) WHERE is_template_rule = true;

-- ============================================================================
-- TRIGGER PARA UPDATED_AT
-- ============================================================================
CREATE TRIGGER update_parsing_rules_updated_at 
    BEFORE UPDATE ON webscraping.parsing_rules 
    FOR EACH ROW EXECUTE FUNCTION webscraping.update_updated_at_column();

-- ============================================================================
-- COMENTARIOS PARA DOCUMENTACIÓN
-- ============================================================================
COMMENT ON TABLE webscraping.parsing_rules IS 'Reglas configurables para parsing y transformación de datos';
COMMENT ON COLUMN webscraping.parsing_rules.source_id IS 'ID de la fuente (NULL para reglas globales)';
COMMENT ON COLUMN webscraping.parsing_rules.rule_type IS 'Tipo de regla: age_range_parser, price_detector, etc.';
COMMENT ON COLUMN webscraping.parsing_rules.entity_type IS 'Entidad objetivo: age_group, price, category, etc.';
COMMENT ON COLUMN webscraping.parsing_rules.priority IS 'Prioridad (menor número = mayor prioridad)';
COMMENT ON COLUMN webscraping.parsing_rules.pattern IS 'Patrón regex para matching';
COMMENT ON COLUMN webscraping.parsing_rules.replacement IS 'Texto de reemplazo o transformación';
COMMENT ON COLUMN webscraping.parsing_rules.config IS 'Configuración JSON flexible para la regla';

-- ============================================================================
-- ÍNDICES GEOESPACIALES ADICIONALES
-- ============================================================================
-- Índices para geolocalización usando PostGIS (si está disponible)
-- Si PostGIS está habilitado, estos índices mejorarán las búsquedas geoespaciales

-- Intentar crear índices geoespaciales (fallarán silenciosamente si PostGIS no está disponible)
DO $$
BEGIN
    -- Crear índice espacial para venues si PostGIS está disponible
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis') THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_venues_location ON webscraping.venues USING gist(ST_Point(lon, lat))';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_organizers_location ON webscraping.organizers USING gist(ST_Point(longitude, latitude))';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        -- Si falla, continuamos sin índices espaciales
        RAISE NOTICE 'PostGIS no está disponible, omitiendo índices geoespaciales';
END;
$$;

-- Índices hash para geohash (alternativa a PostGIS)
CREATE INDEX IF NOT EXISTS idx_venues_geohash 
    ON webscraping.venues USING hash(geohash) 
    WHERE geohash IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_organizers_geohash 
    ON webscraping.organizers USING hash(geohash) 
    WHERE geohash IS NOT NULL;

-- ============================================================================
-- FUNCIONES HELPER PARA PARSING RULES
-- ============================================================================

-- Función para obtener reglas de parsing aplicables
CREATE OR REPLACE FUNCTION webscraping.get_parsing_rules(
    p_source_id INTEGER DEFAULT NULL,
    p_entity_type VARCHAR(50) DEFAULT NULL,
    p_rule_type VARCHAR(50) DEFAULT NULL
) RETURNS TABLE (
    id INTEGER,
    rule_type VARCHAR(50),
    entity_type VARCHAR(50),
    priority INTEGER,
    pattern TEXT,
    replacement TEXT,
    config JSONB,
    description VARCHAR(500)
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        pr.id,
        pr.rule_type,
        pr.entity_type,
        pr.priority,
        pr.pattern,
        pr.replacement,
        pr.config,
        pr.description
    FROM webscraping.parsing_rules pr
    WHERE 
        pr.is_active = true
        AND (p_source_id IS NULL OR pr.source_id IS NULL OR pr.source_id = p_source_id)
        AND (p_entity_type IS NULL OR pr.entity_type = p_entity_type)
        AND (p_rule_type IS NULL OR pr.rule_type = p_rule_type)
    ORDER BY 
        pr.priority ASC,
        pr.source_id NULLS LAST, -- Reglas específicas de fuente tienen prioridad
        pr.created_at ASC;
END;
$$ LANGUAGE plpgsql;

-- Función para aplicar reglas de transformación de texto
CREATE OR REPLACE FUNCTION webscraping.apply_text_transformation(
    input_text TEXT,
    p_source_id INTEGER DEFAULT NULL,
    p_entity_type VARCHAR(50) DEFAULT 'general'
) RETURNS TEXT AS $$
DECLARE
    rule RECORD;
    result_text TEXT := input_text;
BEGIN
    -- Aplicar reglas en orden de prioridad
    FOR rule IN 
        SELECT * FROM webscraping.get_parsing_rules(p_source_id, p_entity_type)
        WHERE pattern IS NOT NULL
    LOOP
        -- Aplicar transformación regex si hay patrón y reemplazo
        IF rule.pattern IS NOT NULL AND rule.replacement IS NOT NULL THEN
            result_text := regexp_replace(result_text, rule.pattern, rule.replacement, 'gi');
        END IF;
    END LOOP;
    
    RETURN result_text;
END;
$$ LANGUAGE plpgsql;

-- Nota: Los permisos para sequences y tablas son otorgados automáticamente
-- por ALTER DEFAULT PRIVILEGES configurado en 001_create_schema_and_basic_tables.sql