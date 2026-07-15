import json
import logging
from datetime import datetime

from mcp.server.fastmcp import FastMCP
from pydantic import Field

from config import config
from db.connection import db
from db.schema import SchemaAccessDenied, schema_service
from export.csv_export import export_to_csv
from sql.generator import generate_sql
from sql.validator import SQLValidationError, validator

mcp = FastMCP("DatabaseAssistant", log_level="ERROR")

# Audit logger
audit_logger = logging.getLogger("audit")
audit_logger.setLevel(logging.INFO)
_handler = logging.FileHandler("audit.log")
_handler.setFormatter(
    logging.Formatter("%(asctime)s | %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
)
audit_logger.addHandler(_handler)


def _audit(query: str, execution_time: float, row_count: int, exported: bool = False):
    audit_logger.info(
        f"query={query} | time={execution_time}s | rows={row_count} | exported={exported}"
    )


def _json(data) -> str:
    return json.dumps(data, indent=2, default=str)


# ─── Schema Exploration Tools ────────────────────────────────────────────────


@mcp.tool(
    name="list_databases",
    description="List all available databases on the connected server.",
)
async def list_databases() -> str:
    try:
        databases = await schema_service.list_databases()
        return _json({"databases": databases})
    except Exception as e:
        return _json({"error": str(e)})


@mcp.tool(
    name="list_schemas",
    description="List all schemas in the connected database. For PostgreSQL returns schema names, for MySQL returns databases.",
)
async def list_schemas() -> str:
    try:
        schemas = await schema_service.list_schemas()
        return _json({"schemas": schemas})
    except Exception as e:
        return _json({"error": str(e)})


@mcp.tool(
    name="list_tables",
    description="List all tables in a schema with their types (BASE TABLE or VIEW) and approximate row counts.",
)
async def list_tables(
    schema: str = Field(
        default="public", description="Schema name (e.g., 'public' for PostgreSQL)"
    ),
) -> str:
    try:
        tables = await schema_service.list_tables(schema)
        return _json({"schema": schema, "tables": tables})
    except SchemaAccessDenied as e:
        return _json({"error": str(e)})
    except Exception as e:
        return _json({"error": str(e)})


@mcp.tool(
    name="describe_table",
    description="Get detailed table information: columns (name, type, nullable, default), constraints (PK, FK, unique), and indexes.",
)
async def describe_table(
    table: str = Field(
        description="Table name. Use 'schema.table' format (e.g., 'public.users') or just 'table' for the default schema."
    ),
) -> str:
    try:
        schema, table_name = _parse_table_ref(table)
        result = await schema_service.describe_table(schema, table_name)
        return _json(result)
    except (SchemaAccessDenied, ValueError) as e:
        return _json({"error": str(e)})
    except Exception as e:
        return _json({"error": str(e)})


@mcp.tool(
    name="describe_relationships",
    description="Show foreign key relationships for a table: both outgoing (this table references others) and incoming (others reference this table).",
)
async def describe_relationships(
    table: str = Field(
        description="Table name in 'schema.table' format (e.g., 'public.orders')"
    ),
) -> str:
    try:
        schema, table_name = _parse_table_ref(table)
        result = await schema_service.describe_relationships(schema, table_name)

        # Format as tree view
        lines = [f"Table: {schema}.{table_name}", ""]
        if result["outgoing_references"]:
            lines.append("Outgoing (this table → others):")
            for ref in result["outgoing_references"]:
                lines.append(
                    f"  ├── {ref['from_column']} → {ref.get('to_schema', schema)}.{ref['to_table']}.{ref['to_column']}"
                )
        else:
            lines.append("Outgoing: None")

        lines.append("")
        if result["incoming_references"]:
            lines.append("Incoming (others → this table):")
            for ref in result["incoming_references"]:
                lines.append(
                    f"  ├── {ref.get('from_schema', schema)}.{ref['from_table']}.{ref['from_column']} → {ref['to_column']}"
                )
        else:
            lines.append("Incoming: None")

        return "\n".join(lines)
    except (SchemaAccessDenied, ValueError) as e:
        return _json({"error": str(e)})
    except Exception as e:
        return _json({"error": str(e)})


@mcp.tool(
    name="sample_data",
    description="Get a quick preview of data in a table. Returns the first N rows to help understand data format and contents.",
)
async def sample_data(
    table: str = Field(description="Table name in 'schema.table' format"),
    limit: int = Field(
        default=5, description="Number of rows to return (1-50, default: 5)"
    ),
) -> str:
    try:
        schema, table_name = _parse_table_ref(table)
        schema_service._check_schema_access(schema)

        limit = max(1, min(50, limit))
        query = f"SELECT * FROM {schema}.{table_name} LIMIT {limit}"
        result = await db.execute_query(query)
        return _json(result)
    except (SchemaAccessDenied, ValueError) as e:
        return _json({"error": str(e)})
    except Exception as e:
        return _json({"error": str(e)})


# ─── Query Tools ─────────────────────────────────────────────────────────────


@mcp.tool(
    name="validate_sql",
    description="Check if a SQL query is safe to execute. Validates that it is read-only, single-statement, and contains no dangerous operations. Use before run_sql to preview validation.",
)
async def validate_sql_tool(
    query: str = Field(description="SQL query to validate"),
) -> str:
    try:
        validated = validator.validate(query)
        return _json(
            {
                "valid": True,
                "validated_query": validated,
                "message": "Query is safe to execute.",
            }
        )
    except SQLValidationError as e:
        return _json({"valid": False, "error": str(e)})


@mcp.tool(
    name="run_sql",
    description="Execute a read-only SQL query. The query is validated for safety before execution. Supports pagination (100 rows per page). Returns columns, rows, row count, and execution time.",
)
async def run_sql(
    query: str = Field(description="SQL SELECT query to execute"),
    page: int = Field(
        default=1, description="Page number for pagination (100 rows per page)"
    ),
) -> str:
    try:
        validated_query = validator.validate(query)
    except SQLValidationError as e:
        return _json({"error": f"Validation failed: {e}"})

    page_size = 100
    offset = (max(1, page) - 1) * page_size

    # Apply pagination via OFFSET/LIMIT override
    paginated_query = _apply_pagination(validated_query, page_size, offset)

    try:
        result = await db.execute_query(paginated_query)
        _audit(query, result["execution_time_seconds"], result["row_count"])

        result["page"] = page
        result["page_size"] = page_size
        result["has_more"] = result["row_count"] == page_size
        return _json(result)
    except Exception as e:
        return _json({"error": f"Execution failed: {e}"})


@mcp.tool(
    name="explain_query",
    description="Run EXPLAIN ANALYZE on a SQL query to show the execution plan. Helps understand performance characteristics like index usage, sequential scans, and estimated costs.",
)
async def explain_query(
    query: str = Field(description="SQL SELECT query to explain"),
) -> str:
    try:
        validated_query = validator.validate(query)
    except SQLValidationError as e:
        return _json({"error": f"Validation failed: {e}"})

    if config.db_type.value == "postgresql":
        explain_sql = f"EXPLAIN (ANALYZE, FORMAT TEXT) {validated_query}"
    else:
        explain_sql = f"EXPLAIN ANALYZE {validated_query}"

    try:
        result = await db.execute_raw(explain_sql)
        return _json({"query": validated_query, "execution_plan": result})
    except Exception as e:
        return _json({"error": f"EXPLAIN failed: {e}"})


# ─── Generation & Export Tools ───────────────────────────────────────────────


@mcp.tool(
    name="generate_sql",
    description="Generate a SQL query from a natural language question. Uses the database schema as context and an LLM to produce a valid SELECT query. The generated query is validated for safety.",
)
async def generate_sql_tool(
    question: str = Field(
        description="Natural language question (e.g., 'What are the top 10 customers by order count?')"
    ),
    schema: str = Field(
        default="public", description="Schema to use for context"
    ),
) -> str:
    try:
        schema_context = await schema_service.get_schema_context(schema)
    except SchemaAccessDenied as e:
        return _json({"error": str(e)})
    except Exception as e:
        return _json({"error": f"Failed to load schema context: {e}"})

    result = generate_sql(question, schema_context)
    return _json(result)


@mcp.tool(
    name="export_csv",
    description="Execute a SQL query and export results as a CSV file. The query is validated for safety. Returns the file path of the generated CSV.",
)
async def export_csv_tool(
    query: str = Field(description="SQL SELECT query to export"),
) -> str:
    try:
        validated_query = validator.validate(query)
    except SQLValidationError as e:
        return _json({"error": f"Validation failed: {e}"})

    try:
        result = await db.execute_query(validated_query)
        filepath = export_to_csv(result["columns"], result["rows"], query)
        _audit(
            query, result["execution_time_seconds"], result["row_count"], exported=True
        )
        return _json(
            {
                "file_path": filepath,
                "row_count": result["row_count"],
                "columns": result["columns"],
                "execution_time_seconds": result["execution_time_seconds"],
            }
        )
    except Exception as e:
        return _json({"error": f"Export failed: {e}"})


# ─── Helpers ─────────────────────────────────────────────────────────────────


def _parse_table_ref(table: str) -> tuple[str, str]:
    """Parse 'schema.table' or 'table' into (schema, table)."""
    parts = table.split(".")
    if len(parts) == 2:
        return parts[0], parts[1]
    elif len(parts) == 1:
        default_schema = config.allowed_schemas[0] if config.allowed_schemas else "public"
        return default_schema, parts[0]
    else:
        raise ValueError(f"Invalid table reference: '{table}'. Use 'schema.table' format.")


def _apply_pagination(query: str, limit: int, offset: int) -> str:
    """Apply pagination to a validated query by rewriting LIMIT/OFFSET."""
    import sqlglot
    from sqlglot import exp

    try:
        statements = sqlglot.parse(query, dialect=validator.dialect)
        if not statements:
            return query
        stmt = statements[0]
        if isinstance(stmt, exp.Select):
            stmt = stmt.limit(limit).offset(offset)
            return stmt.sql(dialect=validator.dialect)
    except Exception:
        pass
    return query


if __name__ == "__main__":
    mcp.run(transport="stdio")
