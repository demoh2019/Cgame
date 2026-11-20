extends RefCounted
## Pure analytic terrain functions shared by the base heightfield and streamed cells.
## Keeping a single height function avoids seams when forest cells unload/reload.

static func height_at(x: float, z: float) -> float:
    return 1.7 * sin(x * 0.058) * cos(z * 0.063) \
        + 0.85 * sin((x + z) * 0.135) \
        + 0.25 * sin(x * 0.47) * cos(z * 0.39)


static func normal_at(x: float, z: float) -> Vector3:
    var e: float = 0.3
    var dx: float = (height_at(x + e, z) - height_at(x - e, z)) / (2.0 * e)
    var dz: float = (height_at(x, z + e) - height_at(x, z - e)) / (2.0 * e)
    return Vector3(-dx, 1.0, -dz).normalized()
