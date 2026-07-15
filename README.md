# Database Assistant MCP Server

A read-only MCP (Model Context Protocol) server for database exploration and querying. Connect any MCP-compatible client (AWS Kiro, Claude Desktop, etc.) to your PostgreSQL or MySQL database and explore schemas, run queries, generate SQL from natural language, and export results as CSV.

## Features

- **Schema Discovery** — List databases, schemas, tables, columns, constraints, indexes, and foreign key relationships
- **Safe Query Execution** — AST-based SQL validation ensures only read-only queries run
- **Natural Language to SQL** — Describe what you want in plain English and get a validated SQL query
- **CSV Export** — Export any query result to a CSV file
- **Query Explanation** — Run EXPLAIN ANALYZE to understand query performance
- **Pagination** — Large results are paginated (100 rows/page) automatically
- **Audit Logging** — Every query is logged with timestamp, execution time, and row count

## Tools

| Tool | Description |
|------|-------------|
| `list_databases` | List all databases on the server |
| `list_schemas` | List schemas (filtered by allowlist) |
| `list_tables` | Tables in a schema with types and row counts |
| `describe_table` | Columns, types, constraints, and indexes |
| `describe_relationships` | Foreign key tree (incoming + outgoing) |
| `sample_data` | Quick N-row preview of a table |
| `validate_sql` | Check if a query is safe before running |
| `run_sql` | Execute a validated read-only query |
| `explain_query` | EXPLAIN ANALYZE with execution plan |
| `generate_sql` | Natural language → SQL (LLM-powered) |
| `export_csv` | Execute query and save results as CSV |

## Security

This server enforces strict read-only access:

- **AST-based validation** — SQL is parsed into an abstract syntax tree using [sqlglot](https://github.com/tobymao/sqlglot), not regex
- **Blocked operations** — INSERT, UPDATE, DELETE, DROP, ALTER, TRUNCATE, CREATE, GRANT, REVOKE, COPY, CALL
- **Single-statement only** — Multi-statement queries (`;` separated) are rejected
- **Dangerous function blocking** — `pg_read_file`, `lo_export`, `dblink`, `LOAD_FILE`, etc.
- **Automatic LIMIT** — Queries without a LIMIT get one injected (default: 1000 rows max)
- **Query timeout** — Enforced at the database level (default: 10 seconds)
- **Schema allowlist** — Restrict access to specific schemas only
- **Generated SQL re-validation** — LLM-generated queries pass through the same validator

## Prerequisites

- Python 3.10+
- [uv](https://docs.astral.sh/uv/) package manager
- PostgreSQL or MySQL database

## Setup

1. **Clone and install dependencies:**

```bash
cd /path/to/RDS
uv sync
```

2. **Configure environment:**

```bash
cp .env.example .env
# Edit .env with your database credentials
```

3. **Seed a test database (optional):**

```bash
psql -U postgres -f seed.sql
```

This creates an `ecommerce` database with 50 tables and ~25,000 rows across customers, products, orders, analytics, support, and more.

## Configuration

Set these environment variables (via `.env` file or system environment):

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DB_HOST` | Yes | — | Database hostname or RDS endpoint |
| `DB_PORT` | No | `5432` | Database port |
| `DB_NAME` | Yes | — | Database name |
| `DB_USER` | Yes | — | Database user (use a read-only user) |
| `DB_PASSWORD` | Yes | — | Database password |
| `DB_TYPE` | No | `postgresql` | `postgresql` or `mysql` |
| `ALLOWED_SCHEMAS` | No | (all) | Comma-separated schema allowlist |
| `QUERY_TIMEOUT` | No | `10` | Max query execution time (seconds) |
| `MAX_ROWS` | No | `1000` | Maximum rows returned per query |
| `CSV_EXPORT_DIR` | No | `/tmp/db_exports` | Directory for CSV exports |
| `OPENAI_BASE_URL` | No | — | LLM API endpoint (for `generate_sql`) |
| `OPENAI_API_KEY` | No | — | LLM API key (for `generate_sql`) |
| `MODEL` | No | `bedrock.claude-sonnet-4-6` | LLM model ID |

## Usage

### With AWS Kiro

Add to your Kiro MCP configuration:

```json
{
  "mcpServers": {
    "database-assistant": {
      "command": "/opt/homebrew/bin/uv",
      "args": ["run", "--directory", "/path/to/database_mcp_server", "mcp_server.py"],
      "env": {
        "DB_HOST": "your-rds-endpoint.rds.amazonaws.com",
        "DB_PORT": "5432",
        "DB_NAME": "ecommerce",
        "DB_USER": "readonly_user",
        "DB_PASSWORD": "your_password",
        "DB_TYPE": "postgresql",
        "ALLOWED_SCHEMAS": "store"
      }
    }
  }
}
```

### With Claude Desktop

Add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "database-assistant": {
      "command": "uv",
      "args": ["run", "--directory", "/path/to/RDS", "mcp_server.py"]
    }
  }
}
```

### With MCP Inspector (for testing)

```bash
uv run mcp dev mcp_server.py
```

### Direct stdio (for development)

```bash
uv run mcp_server.py
```

## Example Workflows

### Explore a database schema

```
User: What tables are in this database?
→ list_tables(schema="store")

User: Tell me about the orders table
→ describe_table(table="store.orders")

User: What relates to orders?
→ describe_relationships(table="store.orders")
```

### Query with natural language

```
User: Show me the top 10 customers by revenue this year
→ generate_sql(question="top 10 customers by total order revenue in 2024")
→ validate_sql(query="SELECT ...")
→ run_sql(query="SELECT ...")
```

### Export data

```
User: Export all orders from last month as CSV
→ generate_sql(question="all orders created in the last 30 days with customer name and total")
→ export_csv(query="SELECT ...")
→ Returns: /tmp/db_exports/export_20240715_143022_a1b2c3d4.csv
```

## Architecture

```
MCP Client (Kiro / Claude Desktop)
        │
        ▼ (stdio)
┌─────────────────────────────┐
│      mcp_server.py          │  FastMCP server, 11 tools
├─────────────────────────────┤
│  sql/validator.py           │  AST-based safety validation (sqlglot)
│  sql/generator.py           │  NL→SQL via OpenAI-compatible LLM
│  db/schema.py               │  Schema introspection service
│  db/connection.py           │  Async connection pool (asyncpg/aiomysql)
│  export/csv_export.py       │  CSV file generation
│  config.py                  │  Environment-based configuration
└─────────────────────────────┘
        │
        ▼
   PostgreSQL / MySQL / AWS RDS
```

## Project Structure

```
.
├── mcp_server.py          # MCP server entry point with tool definitions
├── config.py              # Configuration from environment variables
├── db/
│   ├── connection.py      # Async connection manager with pooling
│   └── schema.py          # Schema introspection service
├── sql/
│   ├── validator.py       # SQL validation (sqlglot AST)
│   └── generator.py       # LLM-based SQL generation
├── export/
│   └── csv_export.py      # CSV export utility
├── seed.sql               # Sample database (50 tables, 25k+ rows)
├── pyproject.toml         # Dependencies and project metadata
├── .env.example           # Environment variable template
└── .gitignore
```

## Creating a Read-Only Database User

For production use, create a dedicated read-only user:

```sql
-- PostgreSQL
CREATE USER readonly_user WITH PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE ecommerce TO readonly_user;
GRANT USAGE ON SCHEMA store TO readonly_user;
GRANT SELECT ON ALL TABLES IN SCHEMA store TO readonly_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA store GRANT SELECT ON TABLES TO readonly_user;
```

```sql
-- MySQL
CREATE USER 'readonly_user'@'%' IDENTIFIED BY 'secure_password';
GRANT SELECT ON ecommerce.* TO 'readonly_user'@'%';
FLUSH PRIVILEGES;
```

## Dependencies

- [mcp](https://pypi.org/project/mcp/) — Model Context Protocol SDK
- [sqlglot](https://github.com/tobymao/sqlglot) — SQL parser for validation
- [asyncpg](https://github.com/MagicStack/asyncpg) — Async PostgreSQL driver
- [aiomysql](https://github.com/aio-libs/aiomysql) — Async MySQL driver
- [openai](https://github.com/openai/openai-python) — LLM API client (for SQL generation)
- [python-dotenv](https://github.com/theskumar/python-dotenv) — Environment variable loading
- [pydantic](https://github.com/pydantic/pydantic) — Data validation

## License

MIT
