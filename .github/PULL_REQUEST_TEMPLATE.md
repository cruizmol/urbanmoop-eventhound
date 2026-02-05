## 📝 Descripción

<!-- Describe los cambios realizados en este PR -->

## 🔗 Issue Relacionado

<!-- Si este PR resuelve un issue, referenciarlo aquí -->
Closes #

## 🏷️ Tipo de Cambio

<!-- Marca con 'x' el tipo de cambio que aplica -->

- [ ] 🐛 Bug fix (corrección de error)
- [ ] ✨ Nueva funcionalidad (feature)
- [ ] 🔨 Refactorización (sin cambios funcionales)
- [ ] 📚 Documentación
- [ ] 🧪 Tests
- [ ] 🔧 Configuración/Tooling
- [ ] ⚡ Mejora de rendimiento
- [ ] 🚀 Deployment/Infraestructura

## 📦 Milestone

<!-- Indica el milestone al que pertenece este PR -->
- [ ] M0 — Database & Infrastructure
- [ ] M1 — Shared Packages
- [ ] M2 — Event Processor
- [ ] M3 — Discovery Worker
- [ ] M4 — Scraping Worker
- [ ] M5 — Classification Worker
- [ ] M6 — Extraction Worker
- [ ] M7 — API Gateway
- [ ] M8 — Testing & CI/CD
- [ ] M9 — Production Deployment

## 🔍 Cambios Realizados

<!-- Lista detallada de cambios específicos -->

-
-
-

## ✅ Checklist

### Código
- [ ] El código sigue las convenciones de estilo del proyecto
- [ ] He realizado una auto-revisión de mi código
- [ ] He comentado el código donde es necesario, especialmente en áreas complejas
- [ ] Los nombres de variables, funciones y clases son descriptivos
- [ ] No hay código comentado o console.logs innecesarios

### Arquitectura
- [ ] Respeta el principio **Single Writer** (solo Event Processor escribe en BD)
- [ ] Los contratos de mensajería son agnósticos de implementación
- [ ] Los workers no escriben directamente en la base de datos
- [ ] Se utilizan los schemas Zod de `@urbanmoop/contracts`
- [ ] Se mantiene la separación de responsabilidades entre servicios

### Documentación
- [ ] He actualizado la documentación correspondiente (si aplica)
- [ ] He añadido comentarios JSDoc a funciones públicas
- [ ] He actualizado el README si era necesario
- [ ] He documentado decisiones de diseño importantes

### Testing
- [ ] He añadido tests unitarios que prueban mi código
- [ ] He añadido tests de integración (si aplica)
- [ ] Todos los tests existentes pasan (`npm test`)
- [ ] La cobertura de tests no ha disminuido

### Database
- [ ] He creado/actualizado migraciones SQL si era necesario
- [ ] He creado scripts de rollback correspondientes
- [ ] He verificado que las migraciones se ejecutan sin errores
- [ ] He actualizado los schemas de Drizzle ORM

### Dependencias
- [ ] He añadido las dependencias necesarias al package.json apropiado
- [ ] No he añadido dependencias innecesarias o duplicadas
- [ ] He verificado las versiones de las dependencias

## 🧪 Testing

### Cómo Probar

<!-- Instrucciones paso a paso para probar los cambios -->

1.
2.
3.

### Casos de Prueba

<!-- Lista de casos de prueba específicos -->

- [ ] Caso 1:
- [ ] Caso 2:
- [ ] Caso 3:

### Tests Ejecutados

```bash
# Comandos de test ejecutados
npm test
npm run test:integration
```

## 📸 Screenshots / Logs

<!-- Si aplica, incluir capturas de pantalla o logs relevantes -->

<details>
<summary>Click para ver logs/screenshots</summary>

```
# Pegar logs aquí si es relevante
```

</details>

## 🔄 Flujo de Mensajes

<!-- Si este PR involucra mensajería event-driven, describir el flujo -->

```
Usuario/API → cmd.X → Worker Y → evt.Y → Event Processor → Base de Datos
```

## ⚠️ Breaking Changes

<!-- ¿Este PR introduce cambios que rompen compatibilidad? -->

- [ ] No hay breaking changes
- [ ] **SÍ hay breaking changes** (describir abajo):

<!-- Si hay breaking changes, describir:
- Qué se rompe
- Cómo migrar
- Alternativas consideradas
-->

## 📋 Notas Adicionales

<!-- Cualquier información adicional relevante para los revisores -->

## 👥 Revisores

<!-- Tag a revisores específicos si es necesario -->
@cruizmol

---

**Checklist del Revisor:**
- [ ] El código es claro y mantenible
- [ ] La arquitectura event-driven se respeta
- [ ] Los tests son adecuados y pasan
- [ ] La documentación está actualizada
- [ ] No hay vulnerabilidades de seguridad evidentes
- [ ] El PR está bien estructurado y es fácil de revisar
