"""Blender原稿适配的无副作用帮助函数；导入本模块不打开文件或改变场景。"""
from mathutils import Matrix, Vector


def affine(scale=(1, 1, 1), offset=(0, 0, 0)):
    """已确认需要改变长宽高的建筑平面才使用非均匀scale。"""
    matrix = Matrix.Diagonal((*scale, 1))
    matrix.translation = Vector(offset)
    return matrix


def mesh_bounds(mesh):
    """传入已烘成世界坐标的源Mesh，返回Blender XYZ范围。"""
    return (Vector(tuple(min(v.co[i] for v in mesh.vertices) for i in range(3))),
            Vector(tuple(max(v.co[i] for v in mesh.vertices) for i in range(3))))


def uniform_grounded_transform(mesh, center_xy, uniform_scale, bottom_z):
    """布局只移动中心，石/器物只均匀缩放，再按真实最低点贴指定地面。"""
    lo, hi = mesh_bounds(mesh)
    center = (lo + hi) * .5
    return affine((uniform_scale,) * 3,
                  (center_xy[0] - center.x * uniform_scale,
                   center_xy[1] - center.y * uniform_scale,
                   bottom_z - lo.z * uniform_scale))


def planar_uv(mesh, metres_per_repeat=(3.2, 3.2), axes=(0, 1), offset=(0, 0)):
    """按米设置已有纹理UV，不写图片。适用于地/板面；器物应保留源展开。"""
    uv = mesh.uv_layers.active or mesh.uv_layers.new(name='UVMap')
    for loop in mesh.loops:
        vertex = mesh.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = (vertex[axes[0]] / metres_per_repeat[0] + offset[0],
                                 vertex[axes[1]] / metres_per_repeat[1] + offset[1])
