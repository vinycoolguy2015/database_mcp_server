import os
from dataclasses import dataclass, field
from enum import Enum

from dotenv import load_dotenv

load_dotenv()


class DBType(str, Enum):
    POSTGRESQL = "postgresql"
    MYSQL = "mysql"


@dataclass
class Config:
    db_host: str = field(default_factory=lambda: os.environ["DB_HOST"])
    db_port: int = field(default_factory=lambda: int(os.getenv("DB_PORT", "5432")))
    db_name: str = field(default_factory=lambda: os.environ["DB_NAME"])
    db_user: str = field(default_factory=lambda: os.environ["DB_USER"])
    db_password: str = field(default_factory=lambda: os.environ["DB_PASSWORD"])
    db_type: DBType = field(
        default_factory=lambda: DBType(os.getenv("DB_TYPE", "postgresql"))
    )
    allowed_schemas: list[str] = field(
        default_factory=lambda: [
            s.strip() for s in os.getenv("ALLOWED_SCHEMAS", "").split(",") if s.strip()
        ]
    )
    query_timeout: int = field(
        default_factory=lambda: int(os.getenv("QUERY_TIMEOUT", "10"))
    )
    max_rows: int = field(default_factory=lambda: int(os.getenv("MAX_ROWS", "1000")))
    csv_export_dir: str = field(
        default_factory=lambda: os.getenv("CSV_EXPORT_DIR", "/tmp/db_exports")
    )
    openai_base_url: str = field(
        default_factory=lambda: os.getenv("OPENAI_BASE_URL", "")
    )
    openai_api_key: str = field(
        default_factory=lambda: os.getenv("OPENAI_API_KEY", "")
    )
    model: str = field(
        default_factory=lambda: os.getenv("MODEL", "")
    )


config = Config()
