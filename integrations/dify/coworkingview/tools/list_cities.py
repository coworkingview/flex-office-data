from collections.abc import Generator
from typing import Any

from dify_plugin import Tool
from dify_plugin.entities.tool import ToolInvokeMessage

from coworkingview_client import Client, render_cities


class ListCitiesTool(Tool):
    def _invoke(self, tool_parameters: dict[str, Any]) -> Generator[ToolInvokeMessage, None, None]:
        result = Client().list_cities(
            locale=tool_parameters.get("locale"),
            country=tool_parameters.get("country"),
        )
        yield self.create_json_message(result)
        yield self.create_text_message(render_cities(result))
