from collections.abc import Generator
from typing import Any

from dify_plugin import Tool
from dify_plugin.entities.tool import ToolInvokeMessage

from coworkingview_client import Client, render_workspaces


class GetWorkspaceTool(Tool):
    def _invoke(self, tool_parameters: dict[str, Any]) -> Generator[ToolInvokeMessage, None, None]:
        result = Client().get_workspace(
            slug=tool_parameters.get("slug"),
            locale=tool_parameters.get("locale"),
        )
        yield self.create_json_message(result)
        yield self.create_text_message(render_workspaces(result))
