"""Apache Airflow provider for the CoworkingView Price Index.

Airflow loads :func:`coworkingview_provider.get_provider_info.get_provider_info`
from the ``apache_airflow_provider`` entry point. That module does not import
the hook, so provider discovery does not open a connection or the network.
"""

from coworkingview_provider._version import __version__

__all__ = ["__version__"]
