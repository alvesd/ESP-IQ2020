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
CONF_HEATER_RUNTIME_ID = "heater_runtime_id"

CONF_WATER_TEMP_SENSOR = "water_temp"
CONF_WATER_TEMP_DAILY_SENSOR = "water_temp_daily"
CONF_WATER_TEMP_MONTHLY_SENSOR = "water_temp_monthly"
CONF_POWER_SENSOR = "power"
CONF_POWER_DAILY_SENSOR = "power_daily"
CONF_POWER_MONTHLY_SENSOR = "power_monthly"
CONF_ENERGY_SENSOR = "energy"
CONF_ENERGY_MONTHLY_SENSOR = "energy_monthly"
CONF_SALT_SENSOR = "salt"
CONF_SALT_DAILY_SENSOR = "salt_daily"
CONF_SALT_MONTHLY_SENSOR = "salt_monthly"
CONF_HEATER_DAILY_SENSOR = "heater_daily"
CONF_HEATER_MONTHLY_SENSOR = "heater_monthly"
CONF_FREE_HEAP_SENSOR = "free_heap"

iq2020_history_ns = cg.esphome_ns.namespace("iq2020_history")
IQ2020History = iq2020_history_ns.class_("IQ2020History", cg.PollingComponent)

_DIAG_TEXT_SCHEMA = text_sensor.text_sensor_schema(entity_category=ENTITY_CATEGORY_DIAGNOSTIC)

_OUTPUT_SENSORS = (
    (CONF_WATER_TEMP_SENSOR, "set_water_temp_history"),
    (CONF_WATER_TEMP_DAILY_SENSOR, "set_water_temp_daily_history"),
    (CONF_WATER_TEMP_MONTHLY_SENSOR, "set_water_temp_monthly_history"),
    (CONF_POWER_SENSOR, "set_power_history"),
    (CONF_POWER_DAILY_SENSOR, "set_power_daily_history"),
    (CONF_POWER_MONTHLY_SENSOR, "set_power_monthly_history"),
    (CONF_ENERGY_SENSOR, "set_energy_history"),
    (CONF_ENERGY_MONTHLY_SENSOR, "set_energy_monthly_history"),
    (CONF_SALT_SENSOR, "set_salt_history"),
    (CONF_SALT_DAILY_SENSOR, "set_salt_daily_history"),
    (CONF_SALT_MONTHLY_SENSOR, "set_salt_monthly_history"),
    (CONF_HEATER_DAILY_SENSOR, "set_heater_daily_history"),
    (CONF_HEATER_MONTHLY_SENSOR, "set_heater_monthly_history"),
    (CONF_FREE_HEAP_SENSOR, "set_free_heap_history"),
)

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
        cv.Optional(CONF_HEATER_RUNTIME_ID): cv.use_id(sensor.Sensor),
        **{cv.Optional(key): _DIAG_TEXT_SCHEMA for key, _ in _OUTPUT_SENSORS},
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
    if CONF_HEATER_RUNTIME_ID in config:
        s = await cg.get_variable(config[CONF_HEATER_RUNTIME_ID])
        cg.add(var.set_heater_runtime_source(s))

    for key, setter in _OUTPUT_SENSORS:
        if key in config:
            ts = await text_sensor.new_text_sensor(config[key])
            cg.add(getattr(var, setter)(ts))
