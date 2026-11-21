def can_build(env, platform):
    return True


def configure(env):
    pass


def get_doc_classes():
    return ["PCGSpatialFilter2D", "PCGSpatialFilter3D", "PCGFoliageScalability3D", "PCGWeightedVariantSelector", "PCGPointTransform3D", "PCGDensitySelector"]


def get_doc_path():
    return "doc_classes"
