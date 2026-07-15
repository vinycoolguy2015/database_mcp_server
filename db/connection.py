import time

import aiomysql
import asyncpg

from config import DBType, config


class ConnectionManager:
    def __init__(self):
        self._pool = None

    async def get_pool(self):
        if self._pool is None:
            if config.db_type == DBType.POSTGRESQL:
                self._pool = await asyncpg.create_pool(
                    host=config.db_host,
                    port=config.db_port,
                    database=config.db_name,
                    user=config.db_user,
                    password=config.db_password,
                    min_size=2,
                    max_size=10,
                    command_timeout=config.query_timeout,
                )
            else:
                self._pool = await aiomysql.create_pool(
                    host=config.db_host,
                    port=config.db_port,
                    db=config.db_name,
                    user=config.db_user,
                    password=config.db_password,
                    minsize=2,
                    maxsize=10,
                    connect_timeout=config.query_timeout,
                )
        return self._pool

    async def execute_query(self, query: str) -> dict:
        pool = await self.get_pool()
        start_time = time.time()

        if config.db_type == DBType.POSTGRESQL:
            async with pool.acquire() as conn:
                await conn.execute(
                    f"SET statement_timeout = '{config.query_timeout}s'"
                )
                rows = await conn.fetch(query)
                columns = [col for col in rows[0].keys()] if rows else []
                data = [dict(row) for row in rows]
        else:
            async with pool.acquire() as conn:
                async with conn.cursor(aiomysql.DictCursor) as cur:
                    await cur.execute(
                        f"SET max_execution_time = {config.query_timeout * 1000}"
                    )
                    await cur.execute(query)
                    data = await cur.fetchall()
                    columns = (
                        [desc[0] for desc in cur.description] if cur.description else []
                    )

        execution_time = round(time.time() - start_time, 3)
        return {
            "columns": columns,
            "rows": data,
            "row_count": len(data),
            "execution_time_seconds": execution_time,
        }

    async def execute_raw(self, query: str) -> list[str]:
        """Execute a query and return raw text rows (for EXPLAIN, SHOW, etc.)."""
        pool = await self.get_pool()

        if config.db_type == DBType.POSTGRESQL:
            async with pool.acquire() as conn:
                await conn.execute(
                    f"SET statement_timeout = '{config.query_timeout}s'"
                )
                rows = await conn.fetch(query)
                return [str(dict(row)) for row in rows]
        else:
            async with pool.acquire() as conn:
                async with conn.cursor() as cur:
                    await cur.execute(
                        f"SET max_execution_time = {config.query_timeout * 1000}"
                    )
                    await cur.execute(query)
                    rows = await cur.fetchall()
                    return [str(row) for row in rows]

    async def close(self):
        if self._pool:
            if config.db_type == DBType.POSTGRESQL:
                await self._pool.close()
            else:
                self._pool.close()
                await self._pool.wait_closed()
            self._pool = None


db = ConnectionManager()
