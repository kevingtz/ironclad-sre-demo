# ADR 002: PostgreSQL como Base de Datos Principal

## Estado
**Aceptado** - 2023-12-07

## Contexto
Para la aplicación CRUD necesitamos seleccionar una base de datos que soporte:
- Transacciones ACID para consistencia de datos
- Esquemas estructurados con validación
- Performance adecuada para operaciones CRUD
- Facilidad de deployment y mantenimiento

Opciones evaluadas:
- PostgreSQL 15
- MySQL 8.0
- MongoDB 6.0
- SQLite (desarrollo local solamente)

## Decisión
**Seleccionamos PostgreSQL 15** como base de datos principal.

## Justificación

### Ventajas de PostgreSQL:

#### 1. **ACID Compliance Robusta**
```sql
-- Transacciones confiables para operaciones críticas
BEGIN;
INSERT INTO users (first_name, last_name, email) VALUES ('John', 'Doe', 'john@example.com');
INSERT INTO audit_log (action, user_id) VALUES ('USER_CREATED', lastval());
COMMIT; -- Garantiza que ambas operaciones succedan o fallen juntas
```

#### 2. **Validación a Nivel de Base de Datos**
```sql
-- Constraints nativos para data integrity
CREATE TABLE users (
    first_name VARCHAR(100) NOT NULL CHECK (first_name ~ '^[A-Za-z\\s-]+$'),
    email VARCHAR(255) UNIQUE NOT NULL,
    phone_number VARCHAR(20) CHECK (phone_number ~ '^(\+1|1)?[-.\s]?\(?[2-9]\d{2}\)?[-.\s]?\d{3}[-.\s]?\d{4}$')
);
```

#### 3. **Performance Superior**
- **Indexing avanzado**: B-tree, Hash, GiST, GIN indexes
- **Query optimizer**: Cost-based optimization muy maduro
- **Parallel queries**: Para operaciones complejas
- **Connection pooling**: Eficiente manejo de conexiones

#### 4. **Extensibilidad y Características Enterprise**
```sql
-- UUID generation nativo
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Full-text search
CREATE INDEX idx_users_search ON users USING gin(to_tsvector('english', first_name || ' ' || last_name));

-- JSON/JSONB support para flexibilidad futura
ALTER TABLE users ADD COLUMN metadata JSONB DEFAULT '{}';
```

#### 5. **Ecosystem y Tooling**
- **pg_stat_statements**: Query performance monitoring
- **pg_dump/pg_restore**: Backup y recovery robustos  
- **pgAdmin**: GUI administration
- **Excellent Node.js support**: Driver `pg` muy maduro

### Comparación con Alternativas:

#### vs MySQL 8.0:
```comparison
PostgreSQL Advantages:
✅ Better standards compliance (SQL)
✅ More advanced data types (JSONB, arrays, custom types)
✅ Better concurrency (MVCC implementation)
✅ More sophisticated query planner
✅ Better regex support

MySQL Advantages:
✅ Slightly faster for simple read-heavy workloads
✅ Larger community/ecosystem
✅ More familiar to many developers

Verdict: PostgreSQL mejor para data integrity y features avanzadas
```

#### vs MongoDB 6.0:
```comparison
PostgreSQL Advantages:
✅ ACID transactions across documents
✅ Structured schema con validation
✅ SQL standard query language
✅ Better consistency guarantees
✅ Mature ecosystem

MongoDB Advantages:
✅ Schema flexibility
✅ Better horizontal scaling
✅ JSON-native storage
✅ Faster for document-centric use cases

Verdict: PostgreSQL mejor para structured CRUD con strong consistency
```

## Implementación

### Schema Design
```sql
-- Optimizado para performance y data integrity
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    first_name VARCHAR(100) NOT NULL CHECK (first_name ~ '^[A-Za-z\\s-]+$'),
    middle_name VARCHAR(100) CHECK (middle_name IS NULL OR middle_name ~ '^[A-Za-z\\s-]*$'),
    last_name VARCHAR(100) NOT NULL CHECK (last_name ~ '^[A-Za-z\\s-]+$'),
    email VARCHAR(255) UNIQUE NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    date_of_birth DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes para performance
CREATE INDEX IF NOT EXISTS idx_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_created_at ON users(created_at DESC);

-- Auto-update trigger para updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

### Connection Configuration
```typescript
// Optimizado para production workloads
export const pool = new Pool({
  max: 20,                    // Maximum connections
  idleTimeoutMillis: 30000,   // Close idle connections after 30s
  connectionTimeoutMillis: 2000, // Fail fast for health checks
});
```

## Implicaciones

### Beneficios Operacionales:
1. **Data Integrity**: Constraints a nivel DB previenen data corruption
2. **Performance**: Indexes optimizados para queries CRUD comunes
3. **Monitoring**: Rich metrics via pg_stat_* views
4. **Backup/Recovery**: Herramientas maduras y confiables

### Consideraciones:
1. **Complexity**: Más complejo que NoSQL para ciertos use cases
2. **Vertical Scaling**: Requiere hardware más potente vs horizontal scaling
3. **Schema Migrations**: Cambios de schema requieren planeación

### Mitigaciones:
- **Migration Strategy**: Usar herramientas como Flyway o Alembic
- **Performance Monitoring**: pg_stat_statements enabled por default
- **Connection Pooling**: PgBouncer para ambientes de alta concurrencia

## Configuración de Producción

### Docker Configuration
```yaml
postgres:
  image: postgres:15-alpine
  environment:
    POSTGRES_DB: ironclad_db
    POSTGRES_USER: ironclad_user
    POSTGRES_PASSWORD: ${DB_PASSWORD}
  volumes:
    - postgres_data:/var/lib/postgresql/data
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U ironclad_user"]
    interval: 10s
    timeout: 5s
    retries: 5
```

### Performance Tuning
```sql
-- Configuraciones para production
-- shared_buffers = 256MB
-- effective_cache_size = 1GB  
-- work_mem = 4MB
-- maintenance_work_mem = 64MB
-- checkpoint_completion_target = 0.9
-- wal_buffers = 16MB
```

## Métricas de Éxito
- **Query Performance**: P95 < 50ms para operaciones CRUD
- **Connection Efficiency**: Pool utilization < 80%
- **Data Integrity**: Zero data corruption incidents
- **Availability**: 99.9% uptime

## Referencias
- [PostgreSQL 15 Documentation](https://www.postgresql.org/docs/15/)
- [Node.js pg Driver](https://node-postgres.com/)
- [PostgreSQL Performance Tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)

## Revisión
Esta decisión será revisada si:
- Query performance no cumple SLOs
- Scaling requirements exceden single-instance capabilities  
- Team expertise cambia significativamente