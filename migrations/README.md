# Migraciones WebScraping - UrbanMoop Backend API

## 📋 Orden de Ejecución Requerido

⚠️ **IMPORTANTE**: Las migraciones deben ejecutarse en este orden específico debido a las dependencias entre tablas:

### 1. **001_create_schema_and_basic_tables.sql**
- **Dependencias**: Ninguna
- **Crea**: 
  - Schema `webscraping` y roles
  - `alembic_version` (control de versiones)
  - `technology_templates` (templates reutilizables CMS/plataformas)
  - Tablas base: `sources`, `venues`, `organizers`, `event_categories`, `age_groups`, `pages`
  - `source_configs`
  - `source_configurations` (configuraciones específicas por sitio)
  - `sitemap_discovery` (auto-discovery de sitemaps)
- **Incluye**: Todos los índices críticos para performance

### 2. **002_create_content_tables.sql**
- **Dependencias**: `001_create_schema_and_basic_tables.sql`
- **Crea**: Tablas de contenido
  - `events`, `posts`, `post_categories`, `related_links`

### 3. **003_create_translation_tables.sql**
- **Dependencias**: `002_create_content_tables.sql`
- **Crea**: Soporte multilingüe
  - `event_translations`, `post_translations`, `venue_translations`
  - `organizer_translations`, `event_category_translations`, `age_group_translations`

### 4. **004_create_parsing_rules.sql**
- **Dependencias**: `001_create_schema_and_basic_tables.sql` (foreign key a technology_templates)
- **Crea**: `parsing_rules` (con soporte para technology templates)

### 5. **005_populate_initial_data.sql**
- **Dependencias**: Todas las anteriores
- **Crea**: Datos iniciales y reglas de parsing

### 6. **verify_sequence_permissions.sql** (Opcional)
- **Dependencias**: Todas las anteriores
- **Funciones**: Verificación y corrección de permisos

## 🔄 Cambios Principales vs. Versión Anterior

### ✅ **Nuevas Tablas Sistema de Separación Tecnológica**

#### `technology_templates`
Templates reutilizables para configuraciones de CMS/plataformas (WordPress, Drupal, etc.)
```sql
- technology_type VARCHAR(50) -- wordpress, drupal, etc.
- template_name VARCHAR(100)
- discovery_config JSONB -- Auto-discovery configs
- parsing_config JSONB -- Parsing rules configs  
- normalization_config JSONB -- Data normalization
```

#### `source_configurations` 
Configuraciones específicas por sitio con version control
```sql
- source_id INTEGER (FK to sources)
- technology_template_id INTEGER (FK to technology_templates)
- overrides_config JSONB -- Site-specific overrides
- politeness_config JSONB -- Rate limiting
- recrawl_config JSONB -- Recrawl intervals
- version INTEGER -- Version control
```

#### `sitemap_discovery`
Auto-discovery de sitemaps con análisis de estructura
```sql
- source_id INTEGER (FK to sources)
- sitemap_url VARCHAR(2000)
- sitemap_type VARCHAR(50) -- index, events, venues, etc.
- content_type VARCHAR(50) -- events, organizers, etc.
- structure_analysis JSONB -- Hierarchical analysis
- temporal_filter_config JSONB -- Temporal filters
```

### ✅ **Tabla `parsing_rules` Actualizada**
Ahora soporta templates tecnológicos:
```sql
+ technology_template_id INTEGER (FK to technology_templates)
+ is_template_rule BOOLEAN -- True si es regla de template
+ applies_to_technology VARCHAR(50) -- wordpress, drupal, etc.
```

### ✅ **Correcciones de Schema según Especificaciones**

#### Tabla `sources`:
- `sitemap_index_url`: **Mantiene NOT NULL** (según especificaciones)
- `robots_allowed`: DEFAULT `false` ✓
- `active`: DEFAULT `false` ✓

#### Tabla `venues`:
- `name`: VARCHAR(200) ✓ (era 500)
- `city`: VARCHAR(100) ✓ (era 200)  
- `region`: VARCHAR(100) ✓ (era 200)
- `country`: VARCHAR(2) DEFAULT 'ES' ✓ (era VARCHAR(100))
- `google_maps_url`: VARCHAR(1000) ✓ (era 500)

#### Tabla `related_links`:
- `+ to_url_norm` VARCHAR(2000) ✓
- `+ to_url_hash` VARCHAR(64) ✓
- Constraint único: `(source_id, to_url_hash)` ✓

### ✅ **Índices Críticos para Performance**

Todos los índices especificados en el documento han sido agregados:

**Índices CRÍTICOS**:
- `uq_pages_source_url_hash` - Deduplicación de URLs
- `idx_pages_status_next_crawl` - Query principal del worker  
- `idx_events_starts_at` - Queries por fecha
- `idx_venues_geohash` - Búsquedas geoespaciales

**Índices Únicos**:
- `uq_organizers_source_slug`
- `uq_event_categories_source_slug` 
- `uq_age_groups_source_slug`
- `uq_related_links_source_url_hash`

## 🔐 Permisos y Sequences

- ✅ **service_role**: Tiene `ALTER DEFAULT PRIVILEGES` para sequences
- ✅ **webscraper**: Tiene `ALTER DEFAULT PRIVILEGES` para sequences
- ✅ **Permisos explícitos**: Cada migración otorga permisos a sequences específicas
- ✅ **Función de verificación**: `webscraping.verify_sequence_permissions()`

## 📊 Beneficios del Sistema de Separación Tecnológica

### **Configuración Jerárquica**:
1. **Technology Template** (WordPress/Yoast base knowledge)
2. **Site-Specific Config** (overrides locales: idioma, ubicación) 
3. **Parsing Rules** (reglas de template + reglas específicas)
4. **Sitemap Discovery** (auto-discovery con filtros temporales)

### **Ventajas Operacionales**:
- ⚡ **Setup nuevo site**: 2 horas → 15 minutos (87% reducción)
- 🔄 **Cambios sin deployment** (configuración en tiempo real)
- 🎯 **Templates reutilizables** para múltiples sites similares
- 📊 **Version control** con rollback de configuraciones
- 🤖 **Auto-discovery** de sitemaps desde robots.txt

## 🚀 Comandos de Ejecución

```bash
# Ejecutar migraciones en orden
psql $DATABASE_URL -f migrations/webscraping/001_create_schema_and_basic_tables.sql  
psql $DATABASE_URL -f migrations/webscraping/002_create_content_tables.sql
psql $DATABASE_URL -f migrations/webscraping/003_create_translation_tables.sql
psql $DATABASE_URL -f migrations/webscraping/004_create_parsing_rules.sql
psql $DATABASE_URL -f migrations/webscraping/005_populate_initial_data.sql

# Verificar permisos (opcional)
psql $DATABASE_URL -f migrations/webscraping/verify_sequence_permissions.sql
psql $DATABASE_URL -c "SELECT * FROM webscraping.verify_sequence_permissions();"
```

## 📋 Validación Post-Migración

```sql
-- Verificar todas las tablas existen
SELECT tablename FROM pg_tables 
WHERE schemaname = 'webscraping' 
ORDER BY tablename;

-- Verificar índices críticos
SELECT indexname FROM pg_indexes 
WHERE schemaname = 'webscraping' 
  AND indexname IN (
    'idx_pages_status_next_crawl',
    'idx_events_starts_at', 
    'uq_pages_source_url_hash',
    'uq_organizers_source_slug'
  );

-- Verificar foreign keys del sistema de templates
SELECT constraint_name, table_name, column_name
FROM information_schema.key_column_usage 
WHERE table_schema = 'webscraping'
  AND constraint_name LIKE '%technology_template%';

-- Verificar permisos de sequences
SELECT * FROM webscraping.verify_sequence_permissions();
```

---

## 📚 Referencias

- **Especificaciones**: `/docs/DATABASE_SCHEMA_SPECIFICATIONS.md`
- **Migration Reference**: `004_technology_separation_schema.py`  
- **Orden recomendado**: Schema → Alembic → Technology Templates → Base Tables → Translations