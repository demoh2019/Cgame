extends SceneTree
## Run with a Cgame binary that supports the Aurora Forest project:
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_atmosphere.gd
## The test is deterministic and uses no real-time sleeps or GPU timing.

const AtmosphereCycle = preload("res://scripts/atmosphere_cycle.gd")
const SKY = preload("res://shaders/atmosphere.gdshader")


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Forest atmosphere smoke FAILED: " + message)
    quit(1)


func _run() -> void:
    var sun := DirectionalLight3D.new()
    sun.name = "TestSun"
    root.add_child(sun)
    var environment := Environment.new()
    var sky_material := ShaderMaterial.new()
    sky_material.shader = SKY

    var cycle := AtmosphereCycle.new()
    cycle.name = "TestAtmosphere"
    root.add_child(cycle)
    cycle.paused = true
    cycle.configure(sun, environment, sky_material)
    var first_updates: int = cycle.get_update_count()
    if first_updates != 1:
        _fail("configure should apply the first atmosphere immediately")
        return

    cycle.set_clock(12.0)
    cycle.set_weather(AtmosphereCycle.WEATHER_CLEAR)
    var clear_fog: float = environment.fog_density
    var noon_energy: float = sun.light_energy
    var day_state: Dictionary = cycle.sample_state(12.0, AtmosphereCycle.WEATHER_CLEAR)
    if noon_energy <= 1.0 or float(day_state["aurora"]) > 0.01:
        _fail("noon must be brightly lit without aurora")
        return

    cycle.set_clock(0.0)
    var night_state: Dictionary = cycle.sample_state(0.0, AtmosphereCycle.WEATHER_CLEAR)
    if sun.light_energy > 0.1 or float(night_state["aurora"]) < 0.8:
        _fail("midnight must disable direct sunlight and enable aurora")
        return
    if float(sky_material.get_shader_parameter("aurora_intensity")) < 0.8:
        _fail("aurora intensity was not passed into the sky shader")
        return

    cycle.set_weather(AtmosphereCycle.WEATHER_CLOUDY)
    if not (float(cycle.sample_state(0.0, AtmosphereCycle.WEATHER_CLOUDY)["clouds"]) >
            float(night_state["clouds"])):
        _fail("cloudy weather must increase cloud cover")
        return
    cycle.set_weather(AtmosphereCycle.WEATHER_MIST)
    if environment.fog_density <= clear_fog:
        _fail("mist must increase fog density")
        return
    if cycle.get_weather_name() != "Туман":
        _fail("weather name must reflect active preset")
        return
    cycle.cycle_weather()
    if cycle.weather_mode != AtmosphereCycle.WEATHER_CLEAR:
        _fail("weather selection did not wrap from mist to clear")
        return

    cycle.set_clock(23.5)
    cycle.skip_hours(2.0)
    if not is_equal_approx(cycle.day_hours, 1.5):
        _fail("24-hour clock did not wrap")
        return

    # Pausing freezes the clock, but changing weather still updates the visuals.
    var frozen: float = cycle.day_hours
    cycle._process(2.0)
    if cycle.day_hours != frozen:
        _fail("paused clock advanced")
        return
    cycle.paused = false
    cycle.set_clock(6.0)
    var updates: int = cycle.get_update_count()
    cycle._process(0.10)
    if cycle.get_update_count() != updates:
        _fail("atmosphere updated too often; sky radiance work must be throttled")
        return
    cycle._process(0.41)
    if cycle.get_update_count() != updates + 1:
        _fail("atmosphere failed to update after the throttle interval")
        return
    if cycle.day_hours <= 6.0:
        _fail("time did not advance when unpaused")
        return

    root.remove_child(cycle)
    root.remove_child(sun)
    cycle.free()
    sun.free()
    print("Forest atmosphere smoke PASSED: solar cycle, night aurora, weather, old clock, pause and throttling")
    quit(0)
