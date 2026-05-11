from __future__ import annotations

import uvicorn

from backend_config import settings


def main() -> None:
    host = settings.mobile_api_host or "0.0.0.0"
    try:
        port = int(settings.mobile_api_port or "8000")
    except ValueError:
        port = 8000

    uvicorn.run("mobile_api:app", host=host, port=port, reload=False)


if __name__ == "__main__":
    main()