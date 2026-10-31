from typing import Any

from dify_plugin import ToolProvider


class CoworkingviewProvider(ToolProvider):
    def _validate_credentials(self, credentials: dict[str, Any]) -> None:
        """The public CoworkingView API does not use an API key."""
        return None
