extends RefCounted
## Blob shadow fallback.
const BlobShadow = preload("res://scripts/client/blob_shadow.gd")


func run(t) -> void:
	t.current = "blob shadows only without sun shadows"
	t.check(BlobShadow.wanted(false), "Performance (no shadows) gets blobs")
	t.check(not BlobShadow.wanted(true), "real shadows replace them")
	var a := BlobShadow.make(true)
	var b := BlobShadow.make(false)
	t.check(a.mesh == b.mesh, "one shared mesh")
	t.check(a.is_in_group(BlobShadow.GROUP), "grouped for quality switches")
	a.free()
	b.free()
