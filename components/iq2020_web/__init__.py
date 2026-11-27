from pathlib import Path
import gzip

import esphome.codegen as cg
from esphome.components import web_server_base
from esphome.components.web_server_base import CONF_WEB_SERVER_BASE_ID
import esphome.config_validation as cv
from esphome.const import CONF_ID
from esphome.core import CoroPriority, coroutine_with_priority

DEPENDENCIES = ["web_server"]
AUTO_LOAD = ["web_server_base"]

iq2020_web_ns = cg.esphome_ns.namespace("iq2020_web")
IQ2020WebHandler = iq2020_web_ns.class_("IQ2020WebHandler", cg.Component)

CONFIG_SCHEMA = cv.Schema(
    {
        cv.GenerateID(): cv.declare_id(IQ2020WebHandler),
        cv.GenerateID(CONF_WEB_SERVER_BASE_ID): cv.use_id(web_server_base.WebServerBase),
    }
).extend(cv.COMPONENT_SCHEMA)


@coroutine_with_priority(CoroPriority.WEB)
async def to_code(config):
    html = (Path(__file__).parent / "index.html").read_bytes()
    gz = gzip.compress(html, compresslevel=9)
    cg.extern_progmem_array("IQ2020_WEB_INDEX_GZ", cg.uint8, list(gz))

    base = await cg.get_variable(config[CONF_WEB_SERVER_BASE_ID])
    var = cg.new_Pvariable(
        config[CONF_ID],
        base,
        cg.RawExpression("IQ2020_WEB_INDEX_GZ"),
        len(gz),
    )
    await cg.register_component(var, config)
