import esphome.codegen as cg
from esphome.components import sensor, text_sensor, time
import esphome.config_validation as cv
from esphome.const import CONF_ID, CONF_TIME_ID, ENTITY_CATEGORY_DIAGNOSTIC

DEPENDENCIES = ["time"]
AUTO_LOAD = ["text_sensor"]

CONF_BUCKET_HOURS = "bucket_hours"
CONF_WATER_TEMP_ID = "water_temp_id"
CONF_POWER_IDS = "power_ids"
CONF_ENERGY_IDS = "energy_ids"
CONF_SALT_ID = "salt_id"
CONF_FREE_HEAP_ID = "free_heap_id"

CONF_WATER_TEMP_SENSOR = "water_temp"
CONF_POWER_SENSOR = "power"
CONF_ENERGY_SENSOR = "energy"
CONF_SALT_SENSOR = "salt"
CONF_FREE_HEAP_SENSOR = "free_heap"

iq2020_history_ns = cg.esphome_ns.namespace("iq2020_history")
IQ2020History = iq2020_history_ns.class_("IQ2020History", cg.PollingComponent)

_DIAG_TEXT_SCHEMA = text_sensor.text_sensor_schema(entity_category=ENTITY_CATEGORY_DIAGNOSTIC)

CONFIG_SCHEMA = cv.Schema(
    {
        cv.GenerateID(): cv.declare_id(IQ2020History),
        cv.Required(CONF_TIME_ID): cv.use_id(time.RealTimeClock),
        cv.Optional(CONF_BUCKET_HOURS, default=6): cv.one_of(6, 12, 24, int=True),
        cv.Optional(CONF_WATER_TEMP_ID): cv.use_id(sensor.Sensor),
        cv.Optional(CONF_POWER_IDS, default=[]): cv.ensure_list(cv.use_id(sensor.Sensor)),
        cv.Optional(CONF_ENERGY_IDS, default=[]): cv.ensure_list(cv.use_id(sensor.Sensor)),
        cv.Optional(CONF_SALT_ID): cv.use_id(sensor.Sensor),
        cv.Optional(CONF_FREE_HEAP_ID): cv.use_id(sensor.Sensor),
        cv.Optional(CONF_WATER_TEMP_SENSOR): _DIAG_TEXT_SCHEMA,
        cv.Optional(CONF_POWER_SENSOR): _DIAG_TEXT_SCHEMA,
        cv.Optional(CONF_ENERGY_SENSOR): _DIAG_TEXT_SCHEMA,
        cv.Optional(CONF_SALT_SENSOR): _DIAG_TEXT_SCHEMA,
        cv.Optional(CONF_FREE_HEAP_SENSOR): _DIAG_TEXT_SCHEMA,
    }
).extend(cv.polling_component_schema("60s"))


async def to_code(config):
    var = cg.new_Pvariable(config[CONF_ID])
    await cg.register_component(var, config)

    rtc = await cg.get_variable(config[CONF_TIME_ID])
    cg.add(var.set_time(rtc))
    cg.add(var.set_bucket_hours(config[CONF_BUCKET_HOURS]))

    if CONF_WATER_TEMP_ID in config:
        s = await cg.get_variable(config[CONF_WATER_TEMP_ID])
        cg.add(var.set_water_temp_source(s))
    for pid in config[CONF_POWER_IDS]:
        s = await cg.get_variable(pid)
        cg.add(var.add_power_source(s))
    for eid in config[CONF_ENERGY_IDS]:
        s = await cg.get_variable(eid)
        cg.add(var.add_energy_source(s))
    if CONF_SALT_ID in config:
        s = await cg.get_variable(config[CONF_SALT_ID])
        cg.add(var.set_salt_source(s))
    if CONF_FREE_HEAP_ID in config:
        s = await cg.get_variable(config[CONF_FREE_HEAP_ID])
        cg.add(var.set_free_heap_source(s))

    if CONF_WATER_TEMP_SENSOR in config:
        ts = await text_sensor.new_text_sensor(config[CONF_WATER_TEMP_SENSOR])
        cg.add(var.set_water_temp_history(ts))
    if CONF_POWER_SENSOR in config:
        ts = await text_sensor.new_text_sensor(config[CONF_POWER_SENSOR])
        cg.add(var.set_power_history(ts))
    if CONF_ENERGY_SENSOR in config:
        ts = await text_sensor.new_text_sensor(config[CONF_ENERGY_SENSOR])
        cg.add(var.set_energy_history(ts))
    if CONF_SALT_SENSOR in config:
        ts = await text_sensor.new_text_sensor(config[CONF_SALT_SENSOR])
        cg.add(var.set_salt_history(ts))
    if CONF_FREE_HEAP_SENSOR in config:
        ts = await text_sensor.new_text_sensor(config[CONF_FREE_HEAP_SENSOR])
        cg.add(var.set_free_heap_history(ts))
