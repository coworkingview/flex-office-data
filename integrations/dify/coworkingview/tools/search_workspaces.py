from collections.abc import Generator
from typing import Any

from dify_plugin import Tool
from dify_plugin.entities.tool import ToolInvokeMessage

from coworkingview_client import Client, render_workspaces


class SearchWorkspacesTool(Tool):
    def _invoke(self, tool_parameters: dict[str, Any]) -> Generator[ToolInvokeMessage, None, None]:
        result = Client().search_workspaces(
            city=tool_parameters.get("city"),
            workspace_type=tool_parameters.get("workspace_type"),
            locale=tool_parameters.get("locale"),
            limit=tool_parameters.get("limit"),
        )
        yield self.create_json_message(result)
        yield self.create_text_message(render_workspaces(result))
