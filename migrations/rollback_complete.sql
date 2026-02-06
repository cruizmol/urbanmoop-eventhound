-- ============================================================================
-- ROLLBACK: Eliminar Schema Webscraping Completo
-- Fecha: 2025-11-27
-- Descripción: Rollback completo del schema webscraping
-- ADVERTENCIA: Esta migración eliminará TODOS los datos del schema
-- ============================================================================

-- ============================================================================
-- ADVERTENCIA DE SEGURIDAD
-- ============================================================================
DO $$
BEGIN
    RAISE WARNING '====================================================================';
    RAISE WARNING 'ADVERTENCIA: Esta migración eliminará COMPLETAMENTE el schema webscraping';
    RAISE WARNING 'Todos los datos, tablas, índices y funciones serán eliminados';
    RAISE WARNING 'Esta acción NO es reversible';
    RAISE WARNING '====================================================================';
    
    -- Pausa de seguridad (comentar esta línea para ejecutar)
    -- RAISE EXCEPTION 'Rollback detenido por seguridad. Descomenta la línea anterior para proceder.';
END;
$$;

-- ============================================================================
-- BACKUP DE DATOS CRÍTICOS (OPCIONAL)
-- ============================================================================
-- Antes de eliminar, crear backup de datos importantes si es necesario
/*
CREATE TEMPORARY TABLE temp_sources_backup AS 
SELECT * FROM webscraping.sources WHERE active = true;

CREATE TEMPORARY TABLE temp_parsing_rules_backup AS 
SELECT * FROM webscraping.parsing_rules WHERE is_active = true;
*/

-- ============================================================================
-- REVOCAR PERMISOS (Migration 006)
-- ============================================================================
DO $$
BEGIN
    -- Revocar permisos sólo si las tablas/secuencias existen para mantener el rollback idempotente
    IF to_regclass('webscraping.page_statuses') IS NOT NULL THEN
        REVOKE SELECT ON webscraping.page_statuses FROM webscraper;
        REVOKE SELECT, INSERT, UPDATE, DELETE ON webscraping.page_statuses FROM service_role;
    END IF;

    IF to_regclass('webscraping.page_processing_history') IS NOT NULL THEN
        REVOKE SELECT ON webscraping.page_processing_history FROM webscraper;
        REVOKE SELECT, INSERT, UPDATE, DELETE ON webscraping.page_processing_history FROM service_role;
    END IF;

    IF to_regclass('webscraping.page_status_transitions') IS NOT NULL THEN
        REVOKE SELECT ON webscraping.page_status_transitions FROM webscraper;
        REVOKE SELECT, INSERT, UPDATE, DELETE ON webscraping.page_status_transitions FROM service_role;
    END IF;

    IF to_regclass('webscraping.page_processing_history_id_seq') IS NOT NULL THEN
        REVOKE USAGE, SELECT ON SEQUENCE webscraping.page_processing_history_id_seq FROM service_role;
    END IF;

    IF to_regclass('webscraping.page_status_transitions_id_seq') IS NOT NULL THEN
        REVOKE USAGE, SELECT ON SEQUENCE webscraping.page_status_transitions_id_seq FROM service_role;
    END IF;
END;
$$;

-- ============================================================================
-- ELIMINAR VISTAS
-- ============================================================================
DROP VIEW IF EXISTS webscraping.source_processing_stats;

-- ============================================================================
-- ELIMINAR FUNCIONES
-- ============================================================================
DROP FUNCTION IF EXISTS webscraping.validate_page_status_transition();
DROP FUNCTION IF EXISTS webscraping.get_schema_stats();
DROP FUNCTION IF EXISTS webscraping.apply_text_transformation(TEXT, INTEGER, VARCHAR);
DROP FUNCTION IF EXISTS webscraping.get_parsing_rules(INTEGER, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS webscraping.get_translation(TEXT, INTEGER, TEXT, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS webscraping.update_updated_at_column();

-- ============================================================================
-- ELIMINAR TABLAS EN ORDEN CORRECTO (FK DEPENDENCIES)
-- ============================================================================

-- Eliminar tablas de traducción primero
DROP TABLE IF EXISTS webscraping.age_group_translations CASCADE;
DROP TABLE IF EXISTS webscraping.event_category_translations CASCADE;
DROP TABLE IF EXISTS webscraping.organizer_translations CASCADE;
DROP TABLE IF EXISTS webscraping.venue_translations CASCADE;
DROP TABLE IF EXISTS webscraping.post_translations CASCADE;
DROP TABLE IF EXISTS webscraping.event_translations CASCADE;

-- Eliminar tablas de parsing rules
DROP TABLE IF EXISTS webscraping.parsing_rules CASCADE;

-- Eliminar tablas de relaciones
DROP TABLE IF EXISTS webscraping.post_categories CASCADE;
DROP TABLE IF EXISTS webscraping.related_links CASCADE;

-- Eliminar tablas de contenido principal
DROP TABLE IF EXISTS webscraping.posts CASCADE;
DROP TABLE IF EXISTS webscraping.events CASCADE;

-- Eliminar foreign keys y columnas de pages (migration 006)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_pages_status'
        AND table_schema = 'webscraping'
        AND table_name = 'pages'
    ) THEN
        ALTER TABLE webscraping.pages DROP CONSTRAINT fk_pages_status;
    END IF;
END $$;

ALTER TABLE webscraping.pages
DROP COLUMN IF EXISTS last_error_at,
DROP COLUMN IF EXISTS last_error_message,
DROP COLUMN IF EXISTS last_error_code,
DROP COLUMN IF EXISTS retries_count,
DROP COLUMN IF EXISTS crawler_type,
DROP COLUMN IF EXISTS response_time_ms,
DROP COLUMN IF EXISTS scrape_completed_at,
DROP COLUMN IF EXISTS scrape_started_at,
DROP COLUMN IF EXISTS processing_completed_at,
DROP COLUMN IF EXISTS processing_started_at,
DROP COLUMN IF EXISTS last_message_type,
DROP COLUMN IF EXISTS last_message_id,
DROP COLUMN IF EXISTS correlation_id;

-- Eliminar tablas de tracking de procesamiento (migration 006)
DROP TABLE IF EXISTS webscraping.page_status_transitions CASCADE;
DROP TABLE IF EXISTS webscraping.page_processing_history CASCADE;
DROP TABLE IF EXISTS webscraping.page_statuses CASCADE;

-- Eliminar tablas de metadatos
DROP TABLE IF EXISTS webscraping.pages CASCADE;
DROP TABLE IF EXISTS webscraping.age_groups CASCADE;
DROP TABLE IF EXISTS webscraping.event_categories CASCADE;
DROP TABLE IF EXISTS webscraping.organizers CASCADE;
DROP TABLE IF EXISTS webscraping.venues CASCADE;

-- Eliminar tablas de configuración
DROP TABLE IF EXISTS webscraping.source_configs CASCADE;

-- Eliminar tabla base
DROP TABLE IF EXISTS webscraping.sources CASCADE;

-- ============================================================================
-- ELIMINAR ÍNDICES RESTANTES (SI QUEDAN)
-- ============================================================================
DO $$
DECLARE
    index_record RECORD;
BEGIN
    -- Eliminar todos los índices del schema webscraping
    FOR index_record IN 
        SELECT indexname 
        FROM pg_indexes 
        WHERE schemaname = 'webscraping'
    LOOP
        EXECUTE 'DROP INDEX IF EXISTS webscraping.' || index_record.indexname || ' CASCADE';
    END LOOP;
END;
$$;

-- ============================================================================
-- ELIMINAR TIPOS DE DATOS PERSONALIZADOS (SI EXISTEN)
-- ============================================================================
DO $$
DECLARE
    type_record RECORD;
BEGIN
    FOR type_record IN 
        SELECT typname 
        FROM pg_type t
        JOIN pg_namespace n ON t.typnamespace = n.oid
        WHERE n.nspname = 'webscraping'
    LOOP
        EXECUTE 'DROP TYPE IF EXISTS webscraping.' || type_record.typname || ' CASCADE';
    END LOOP;
END;
$$;

-- ============================================================================
-- ELIMINAR SECUENCIAS
-- ============================================================================
DO $$
DECLARE
    seq_record RECORD;
BEGIN
    FOR seq_record IN 
        SELECT sequencename
        FROM pg_sequences 
        WHERE schemaname = 'webscraping'
    LOOP
        EXECUTE 'DROP SEQUENCE IF EXISTS webscraping.' || seq_record.sequencename || ' CASCADE';
    END LOOP;
END;
$$;

-- ============================================================================
-- ELIMINAR SCHEMA COMPLETO
-- ============================================================================
DROP SCHEMA IF EXISTS webscraping CASCADE;

-- ============================================================================
-- LIMPIAR EXTENSIONES NO UTILIZADAS (OPCIONAL)
-- ============================================================================
-- Solo eliminar si no se usan en otros schemas
-- DROP EXTENSION IF EXISTS "btree_gin";
-- DROP EXTENSION IF EXISTS "uuid-ossp";

-- ============================================================================
-- VERIFICAR LIMPIEZA COMPLETA
-- ============================================================================
DO $$
DECLARE
    remaining_objects INTEGER;
BEGIN
    -- Verificar que no queden objetos del schema webscraping
    SELECT count(*) INTO remaining_objects
    FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'webscraping';
    
    IF remaining_objects > 0 THEN
        RAISE WARNING 'Advertencia: Quedan % objetos en el schema webscraping', remaining_objects;
    ELSE
        RAISE NOTICE '✅ Schema webscraping eliminado completamente';
    END IF;
    
    -- Verificar que el schema fue eliminado
    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'webscraping') THEN
        RAISE NOTICE '✅ Rollback completado exitosamente';
        RAISE NOTICE 'El schema webscraping ha sido eliminado completamente';
    ELSE
        RAISE WARNING '⚠️  El schema webscraping aún existe';
    END IF;
END;
$$;

-- ============================================================================
-- LOG FINAL
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'ROLLBACK WEBSCRAPING COMPLETADO';
    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'Fecha: %', now();
    RAISE NOTICE 'Acción: Schema webscraping eliminado completamente';
    RAISE NOTICE 'Estado: Rollback exitoso';
    RAISE NOTICE '============================================================================';
END;
$$;