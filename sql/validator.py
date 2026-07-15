import sqlglot
from sqlglot import exp

from config import config

BLOCKED_STATEMENT_KEYWORDS = {
    "INSERT",
    "UPDATE",
    "DELETE",
    "DROP",
    "ALTER",
    "TRUNCATE",
    "CREATE",
    "GRANT",
    "REVOKE",
    "COPY",
    "CALL",
    "EXEC",
    "EXECUTE",
    "LOCK",
    "UNLOCK",
    "MERGE",
    "REPLACE",
}

ALLOWED_FIRST_KEYWORDS = {"SELECT", "WITH", "EXPLAIN", "SHOW", "DESCRIBE", "DESC"}

DANGEROUS_FUNCTIONS = {
    "pg_read_file",
    "pg_write_file",
    "pg_ls_dir",
    "pg_stat_file",
    "lo_import",
    "lo_export",
    "dblink",
    "dblink_exec",
    "load_file",
    "into_outfile",
    "into_dumpfile",
}


class SQLValidationError(Exception):
    pass


class SQLValidator:
    def __init__(self, dialect: str = "postgresql"):
        self.dialect = "postgres" if dialect == "postgresql" else "mysql"

    def validate(self, query: str) -> str:
        """Validate SQL and return the safe (possibly LIMIT-modified) query.

        Raises SQLValidationError if the query is unsafe.
        """
        query = query.strip().rstrip(";")
        if not query:
            raise SQLValidationError("Empty query")

        first_word = query.split()[0].upper()
        if first_word in BLOCKED_STATEMENT_KEYWORDS:
            raise SQLValidationError(
                f"Statement type '{first_word}' is not allowed. Only SELECT queries are permitted."
            )
        if first_word not in ALLOWED_FIRST_KEYWORDS:
            raise SQLValidationError(
                f"Statement type '{first_word}' is not allowed. "
                f"Allowed: {', '.join(sorted(ALLOWED_FIRST_KEYWORDS))}"
            )

        try:
            statements = sqlglot.parse(query, dialect=self.dialect)
        except sqlglot.errors.ParseError as e:
            raise SQLValidationError(f"SQL parse error: {e}")

        statements = [s for s in statements if s is not None]
        if len(statements) == 0:
            raise SQLValidationError("Empty query after parsing")
        if len(statements) > 1:
            raise SQLValidationError(
                "Multiple statements not allowed. Submit one query at a time."
            )

        statement = statements[0]
        self._check_for_writes(statement)
        self._check_for_dangerous_functions(statement)

        if first_word == "SELECT" or first_word == "WITH":
            statement = self._enforce_limit(statement)
            return statement.sql(dialect=self.dialect)

        return query

    def _check_for_writes(self, stmt: exp.Expression):
        """Walk the AST to detect any write operations hidden in subqueries."""
        write_types = (
            exp.Insert,
            exp.Update,
            exp.Delete,
            exp.Drop,
            exp.Alter,
            exp.Create,
        )
        for node in stmt.walk():
            if isinstance(node, write_types):
                raise SQLValidationError(
                    f"Write operation '{type(node).__name__}' detected. "
                    "Only read-only queries are allowed."
                )

    def _check_for_dangerous_functions(self, stmt: exp.Expression):
        """Walk the AST to detect calls to dangerous database functions."""
        for node in stmt.walk():
            if isinstance(node, (exp.Anonymous, exp.Func)):
                func_name = ""
                if hasattr(node, "name"):
                    func_name = node.name
                elif hasattr(node, "this") and isinstance(node.this, str):
                    func_name = node.this
                if func_name.lower() in DANGEROUS_FUNCTIONS:
                    raise SQLValidationError(
                        f"Function '{func_name}' is not allowed for security reasons."
                    )

    def _enforce_limit(self, stmt: exp.Expression) -> exp.Expression:
        """Add or cap LIMIT clause on SELECT statements."""
        if not isinstance(stmt, exp.Select):
            if isinstance(stmt, exp.Union):
                return stmt
            for node in stmt.walk():
                if isinstance(node, exp.Select):
                    stmt = node
                    break
            else:
                return stmt

        limit_node = stmt.args.get("limit")
        if limit_node is None:
            return stmt.limit(config.max_rows)

        try:
            limit_expr = limit_node.expression
            if isinstance(limit_expr, exp.Literal):
                current_limit = int(limit_expr.this)
                if current_limit > config.max_rows:
                    return stmt.limit(config.max_rows)
        except (ValueError, AttributeError):
            pass

        return stmt


validator = SQLValidator(dialect=config.db_type.value)
