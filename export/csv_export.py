import csv
import hashlib
import os
from datetime import datetime

from config import config


def export_to_csv(columns: list[str], rows: list[dict], query: str) -> str:
    """Write query results to a CSV file and return the file path."""
    os.makedirs(config.csv_export_dir, exist_ok=True)

    query_hash = hashlib.md5(query.encode()).hexdigest()[:8]
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"export_{timestamp}_{query_hash}.csv"
    filepath = os.path.join(config.csv_export_dir, filename)

    with open(filepath, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)

    return filepath
