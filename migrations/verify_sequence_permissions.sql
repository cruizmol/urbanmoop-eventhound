-- ============================================================================
-- SCRIPT DE VERIFICACIÓN: Permisos de Sequences en Schema Webscraping
-- Fecha: 2025-11-27
-- Descripción: Verifica que service_role y webscraper tengan permisos correctos
--              en todas las sequences del schema webscraping
-- ============================================================================

-- Función para verificar permisos de sequences
CREATE OR REPLACE FUNCTION webscraping.verify_sequence_permissions()
RETURNS TABLE (
    sequence_name TEXT,
    service_role_usage BOOLEAN,
    service_role_select BOOLEAN,
    webscraper_usage BOOLEAN,
    webscraper_select BOOLEAN,
    status TEXT
) AS $$
DECLARE
    seq_record RECORD;
    has_service_usage BOOLEAN;
    has_service_select BOOLEAN;
    has_webscraper_usage BOOLEAN;
    has_webscraper_select BOOLEAN;
BEGIN
    -- Iterar sobre todas las sequences en el schema webscraping
    FOR seq_record IN 
        SELECT c.relname as seq_name
        FROM pg_class c
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'webscraping'
        AND c.relkind = 'S'
        ORDER BY c.relname
    LOOP
        -- Verificar permisos para service_role
        SELECT 
            has_sequence_privilege('service_role', 'webscraping.' || seq_record.seq_name, 'USAGE'),
            has_sequence_privilege('service_role', 'webscraping.' || seq_record.seq_name, 'SELECT')
        INTO has_service_usage, has_service_select;
        
        -- Verificar permisos para webscraper
        SELECT 
            has_sequence_privilege('webscraper', 'webscraping.' || seq_record.seq_name, 'USAGE'),
            has_sequence_privilege('webscraper', 'webscraping.' || seq_record.seq_name, 'SELECT')
        INTO has_webscraper_usage, has_webscraper_select;
        
        -- Determinar estado
        DECLARE
            seq_status TEXT;
        BEGIN
            IF has_service_usage AND has_service_select AND has_webscraper_usage AND has_webscraper_select THEN
                seq_status := 'OK';
            ELSIF NOT has_service_usage OR NOT has_service_select THEN
                seq_status := 'ERROR: service_role missing permissions';
            ELSIF NOT has_webscraper_usage OR NOT has_webscraper_select THEN
                seq_status := 'ERROR: webscraper missing permissions';
            ELSE
                seq_status := 'ERROR: unknown issue';
            END IF;
            
            RETURN QUERY SELECT 
                seq_record.seq_name::TEXT,
                has_service_usage,
                has_service_select,
                has_webscraper_usage,
                has_webscraper_select,
                seq_status;
        END;
    END LOOP;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCIÓN PARA ARREGLAR PERMISOS FALTANTES
-- ============================================================================

CREATE OR REPLACE FUNCTION webscraping.fix_sequence_permissions()
RETURNS TEXT AS $$
DECLARE
    seq_record RECORD;
    fixes_applied INTEGER := 0;
    result_msg TEXT := '';
BEGIN
    -- Iterar sobre todas las sequences y aplicar permisos faltantes
    FOR seq_record IN 
        SELECT c.relname as seq_name
        FROM pg_class c
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'webscraping'
        AND c.relkind = 'S'
        ORDER BY c.relname
    LOOP
        -- Aplicar permisos para service_role
        EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE webscraping.%I TO service_role', seq_record.seq_name);
        
        -- Aplicar permisos para webscraper  
        EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE webscraping.%I TO webscraper', seq_record.seq_name);
        
        fixes_applied := fixes_applied + 1;
        result_msg := result_msg || format('✓ Fixed permissions for %s', seq_record.seq_name) || E'\n';
    END LOOP;
    
    result_msg := result_msg || format('Total sequences fixed: %s', fixes_applied);
    
    RETURN result_msg;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- CONSULTA PARA VER TODAS LAS SEQUENCES Y SUS PERMISOS
-- ============================================================================

-- Usar esta consulta para verificar permisos:
-- SELECT * FROM webscraping.verify_sequence_permissions();

-- Usar esta función para arreglar permisos:
-- SELECT webscraping.fix_sequence_permissions();

-- ============================================================================
-- CONSULTA ADICIONAL: Ver todos los privilegios DEFAULT del schema
-- ============================================================================

/*
Para ver todos los privilegios por defecto configurados:

SELECT 
    defaclnamespace::regnamespace as schema_name,
    defaclobjtype as object_type,
    defaclacl as privileges
FROM pg_default_acl
WHERE defaclnamespace = 'webscraping'::regnamespace;

-- object_type codes:
-- r = tables (relations)
-- S = sequences  
-- f = functions
-- T = types
*/

-- ============================================================================
-- COMENTARIOS Y DOCUMENTACIÓN
-- ============================================================================

COMMENT ON FUNCTION webscraping.verify_sequence_permissions() 
IS 'Verifica que service_role y webscraper tengan permisos USAGE y SELECT en todas las sequences del schema webscraping';

COMMENT ON FUNCTION webscraping.fix_sequence_permissions() 
IS 'Aplica permisos USAGE y SELECT a service_role y webscraper en todas las sequences del schema webscraping';

-- Mostrar resumen de sequences encontradas
DO $$
DECLARE
    seq_count INTEGER;
BEGIN
    SELECT count(*) INTO seq_count 
    FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'webscraping' AND c.relkind = 'S';
    
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'VERIFICACIÓN DE PERMISOS DE SEQUENCES - SCHEMA WEBSCRAPING';
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'Total sequences encontradas: %', seq_count;
    RAISE NOTICE 'Para verificar permisos ejecuta: SELECT * FROM webscraping.verify_sequence_permissions();';
    RAISE NOTICE 'Para arreglar permisos ejecuta: SELECT webscraping.fix_sequence_permissions();';
    RAISE NOTICE '============================================================================';
END;
$$;