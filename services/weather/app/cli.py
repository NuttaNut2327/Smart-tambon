"""python -m app.cli seed | sync <job> | backfill --start YYYY-MM-DD --end YYYY-MM-DD [--location ID ...]"""

import argparse
import json
from datetime import date

from app.config import get_settings
from app.db import SessionLocal
from app.logging_setup import setup_logging
from app.seed import seed_locations
from app.services.jobs import JOB_TYPES, run_job


def main() -> None:
    setup_logging(get_settings().log_level)
    parser = argparse.ArgumentParser(prog="app.cli")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("seed")
    sync = sub.add_parser("sync")
    sync.add_argument("job", choices=[j for j in JOB_TYPES if j != "backfill"])
    sync.add_argument("--location", type=int, action="append")
    bf = sub.add_parser("backfill", help="historical observations only; never touches archived forecasts")
    bf.add_argument("--start", type=date.fromisoformat, required=True)
    bf.add_argument("--end", type=date.fromisoformat, required=True)
    bf.add_argument("--location", type=int, action="append")
    args = parser.parse_args()

    if args.cmd == "seed":
        with SessionLocal() as db:
            n = seed_locations(db, get_settings().default_timezone)
        print(json.dumps({"seeded_locations": n}))
    elif args.cmd == "sync":
        print(json.dumps(run_job(args.job, location_ids=args.location), default=str, indent=2))
    else:
        print(json.dumps(run_job("backfill", location_ids=args.location, start=args.start, end=args.end),
                         default=str, indent=2))


if __name__ == "__main__":
    main()
