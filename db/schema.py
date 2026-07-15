from config import DBType, config
from db.connection import db


class SchemaAccessDenied(Exception):
    pass


class SchemaService:
    def _check_schema_access(self, schema: str):
        if config.allowed_schemas and schema not in config.allowed_schemas:
            raise SchemaAccessDenied(
                f"Access to schema '{schema}' is not allowed. "
                f"Allowed schemas: {', '.join(config.allowed_schemas)}"
            )

    async def list_databases(self) -> list[dict]:
        if config.db_type == DBType.POSTGRESQL:
            query = """
                SELECT datname AS name
                FROM pg_database
                WHERE datistemplate = false
                ORDER BY datname
            """
        else:
            query = "SHOW DATABASES"

        result = await db.execute_query(query)
        return result["rows"]

    async def list_schemas(self) -> list[dict]:
        if config.db_type == DBType.POSTGRESQL:
            query = """
                SELECT schema_name AS name
                FROM information_schema.schemata
                WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
                ORDER BY schema_name
            """
        else:
            query = f"SELECT SCHEMA_NAME AS name FROM information_schema.schemata ORDER BY SCHEMA_NAME"

        result = await db.execute_query(query)

        if config.allowed_schemas:
            result["rows"] = [
                r for r in result["rows"] if r["name"] in config.allowed_schemas
            ]
        return result["rows"]

    async def list_tables(self, schema: str) -> list[dict]:
        self._check_schema_access(schema)

        if config.db_type == DBType.POSTGRESQL:
            query = f"""
                SELECT
                    t.table_name AS name,
                    t.table_type AS type,
                    COALESCE(s.n_live_tup, 0) AS approximate_row_count
                FROM information_schema.tables t
                LEFT JOIN pg_stat_user_tables s
                    ON s.schemaname = t.table_schema AND s.relname = t.table_name
                WHERE t.table_schema = '{schema}'
                ORDER BY t.table_name
            """
        else:
            query = f"""
                SELECT
                    TABLE_NAME AS name,
                    TABLE_TYPE AS type,
                    TABLE_ROWS AS approximate_row_count
                FROM information_schema.tables
                WHERE TABLE_SCHEMA = '{schema}'
                ORDER BY TABLE_NAME
            """

        result = await db.execute_query(query)
        return result["rows"]

    async def describe_table(self, schema: str, table: str) -> dict:
        self._check_schema_access(schema)

        if config.db_type == DBType.POSTGRESQL:
            columns_query = f"""
                SELECT
                    column_name,
                    data_type,
                    is_nullable,
                    column_default,
                    character_maximum_length
                FROM information_schema.columns
                WHERE table_schema = '{schema}' AND table_name = '{table}'
                ORDER BY ordinal_position
            """
            constraints_query = f"""
                SELECT
                    tc.constraint_name,
                    tc.constraint_type,
                    kcu.column_name
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                    ON tc.constraint_name = kcu.constraint_name
                    AND tc.table_schema = kcu.table_schema
                WHERE tc.table_schema = '{schema}' AND tc.table_name = '{table}'
                ORDER BY tc.constraint_type, kcu.ordinal_position
            """
            indexes_query = f"""
                SELECT
                    indexname AS index_name,
                    indexdef AS index_definition
                FROM pg_indexes
                WHERE schemaname = '{schema}' AND tablename = '{table}'
                ORDER BY indexname
            """
        else:
            columns_query = f"""
                SELECT
                    COLUMN_NAME AS column_name,
                    DATA_TYPE AS data_type,
                    IS_NULLABLE AS is_nullable,
                    COLUMN_DEFAULT AS column_default,
                    CHARACTER_MAXIMUM_LENGTH AS character_maximum_length
                FROM information_schema.columns
                WHERE TABLE_SCHEMA = '{schema}' AND TABLE_NAME = '{table}'
                ORDER BY ORDINAL_POSITION
            """
            constraints_query = f"""
                SELECT
                    tc.CONSTRAINT_NAME AS constraint_name,
                    tc.CONSTRAINT_TYPE AS constraint_type,
                    kcu.COLUMN_NAME AS column_name
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                    ON tc.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME
                    AND tc.TABLE_SCHEMA = kcu.TABLE_SCHEMA
                WHERE tc.TABLE_SCHEMA = '{schema}' AND tc.TABLE_NAME = '{table}'
                ORDER BY tc.CONSTRAINT_TYPE, kcu.ORDINAL_POSITION
            """
            indexes_query = f"""
                SELECT
                    INDEX_NAME AS index_name,
                    CONCAT('CREATE INDEX ON ', TABLE_NAME, ' (', GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX), ')') AS index_definition
                FROM information_schema.statistics
                WHERE TABLE_SCHEMA = '{schema}' AND TABLE_NAME = '{table}'
                GROUP BY INDEX_NAME, TABLE_NAME
                ORDER BY INDEX_NAME
            """

        columns_result = await db.execute_query(columns_query)
        constraints_result = await db.execute_query(constraints_query)
        indexes_result = await db.execute_query(indexes_query)

        return {
            "schema": schema,
            "table": table,
            "columns": columns_result["rows"],
            "constraints": constraints_result["rows"],
            "indexes": indexes_result["rows"],
        }

    async def describe_relationships(self, schema: str, table: str) -> dict:
        self._check_schema_access(schema)

        if config.db_type == DBType.POSTGRESQL:
            outgoing_query = f"""
                SELECT
                    kcu.column_name AS from_column,
                    ccu.table_schema AS to_schema,
                    ccu.table_name AS to_table,
                    ccu.column_name AS to_column,
                    tc.constraint_name
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                    ON tc.constraint_name = kcu.constraint_name
                    AND tc.table_schema = kcu.table_schema
                JOIN information_schema.constraint_column_usage ccu
                    ON ccu.constraint_name = tc.constraint_name
                    AND ccu.table_schema = tc.table_schema
                WHERE tc.constraint_type = 'FOREIGN KEY'
                    AND tc.table_schema = '{schema}'
                    AND tc.table_name = '{table}'
            """
            incoming_query = f"""
                SELECT
                    kcu.table_schema AS from_schema,
                    kcu.table_name AS from_table,
                    kcu.column_name AS from_column,
                    ccu.column_name AS to_column,
                    tc.constraint_name
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                    ON tc.constraint_name = kcu.constraint_name
                    AND tc.table_schema = kcu.table_schema
                JOIN information_schema.constraint_column_usage ccu
                    ON ccu.constraint_name = tc.constraint_name
                    AND ccu.table_schema = tc.table_schema
                WHERE tc.constraint_type = 'FOREIGN KEY'
                    AND ccu.table_schema = '{schema}'
                    AND ccu.table_name = '{table}'
            """
        else:
            outgoing_query = f"""
                SELECT
                    COLUMN_NAME AS from_column,
                    REFERENCED_TABLE_SCHEMA AS to_schema,
                    REFERENCED_TABLE_NAME AS to_table,
                    REFERENCED_COLUMN_NAME AS to_column,
                    CONSTRAINT_NAME AS constraint_name
                FROM information_schema.key_column_usage
                WHERE TABLE_SCHEMA = '{schema}'
                    AND TABLE_NAME = '{table}'
                    AND REFERENCED_TABLE_NAME IS NOT NULL
            """
            incoming_query = f"""
                SELECT
                    TABLE_SCHEMA AS from_schema,
                    TABLE_NAME AS from_table,
                    COLUMN_NAME AS from_column,
                    REFERENCED_COLUMN_NAME AS to_column,
                    CONSTRAINT_NAME AS constraint_name
                FROM information_schema.key_column_usage
                WHERE REFERENCED_TABLE_SCHEMA = '{schema}'
                    AND REFERENCED_TABLE_NAME = '{table}'
                    AND REFERENCED_TABLE_NAME IS NOT NULL
            """

        outgoing_result = await db.execute_query(outgoing_query)
        incoming_result = await db.execute_query(incoming_query)

        return {
            "table": f"{schema}.{table}",
            "outgoing_references": outgoing_result["rows"],
            "incoming_references": incoming_result["rows"],
        }

    async def get_schema_context(self, schema: str) -> str:
        """Get compact DDL-like representation for SQL generation context using a single query."""
        self._check_schema_access(schema)

        if config.db_type == DBType.POSTGRESQL:
            query = f"""
                SELECT
                    c.table_name,
                    c.column_name,
                    c.data_type,
                    c.is_nullable,
                    CASE WHEN pk.column_name IS NOT NULL THEN 'PK' ELSE '' END AS is_pk
                FROM information_schema.columns c
                LEFT JOIN (
                    SELECT kcu.table_name, kcu.column_name
                    FROM information_schema.table_constraints tc
                    JOIN information_schema.key_column_usage kcu
                        ON tc.constraint_name = kcu.constraint_name
                        AND tc.table_schema = kcu.table_schema
                    WHERE tc.constraint_type = 'PRIMARY KEY'
                        AND tc.table_schema = '{schema}'
                ) pk ON pk.table_name = c.table_name AND pk.column_name = c.column_name
                WHERE c.table_schema = '{schema}'
                ORDER BY c.table_name, c.ordinal_position
            """
        else:
            query = f"""
                SELECT
                    c.TABLE_NAME AS table_name,
                    c.COLUMN_NAME AS column_name,
                    c.DATA_TYPE AS data_type,
                    c.IS_NULLABLE AS is_nullable,
                    CASE WHEN c.COLUMN_KEY = 'PRI' THEN 'PK' ELSE '' END AS is_pk
                FROM information_schema.columns c
                WHERE c.TABLE_SCHEMA = '{schema}'
                ORDER BY c.TABLE_NAME, c.ORDINAL_POSITION
            """

        result = await db.execute_query(query)

        tables = {}
        for row in result["rows"]:
            tname = row["table_name"]
            if tname not in tables:
                tables[tname] = {"cols": [], "pks": []}
            nullable = "NULL" if row["is_nullable"] == "YES" else "NOT NULL"
            tables[tname]["cols"].append(f"  {row['column_name']} {row['data_type']} {nullable}")
            if row["is_pk"] == "PK":
                tables[tname]["pks"].append(row["column_name"])

        context_parts = []
        for tname, info in tables.items():
            ddl = f"TABLE {schema}.{tname} (\n"
            ddl += ",\n".join(info["cols"])
            if info["pks"]:
                ddl += f",\n  PRIMARY KEY ({', '.join(info['pks'])})"
            ddl += "\n)"
            context_parts.append(ddl)

        return "\n\n".join(context_parts)


schema_service = SchemaService()
