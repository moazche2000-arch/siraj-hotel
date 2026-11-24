"""Model and render the Siraj Hotel set and cast in Blender 4.5.

blender --background --factory-startup --python-exit-code 1 --python art/render_hotel.py
"""

import math
import random
import tempfile
from array import array
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
MAP_WIDTH, MAP_HEIGHT = 902, 566
UNIT = 0.02
SPRITE = 128
MESHES = {}


def linear(channel):
    return channel / 12.92 if channel < 0.04045 else ((channel + 0.055) / 1.055) ** 2.4


def material(name, hex_color, roughness=0.74, metallic=0, emission=0):
    channels = [linear(int(hex_color[i:i + 2], 16) / 255) for i in (0, 2, 4)]
    color = (*channels, 1)
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Emission Color"].default_value = color
    shader.inputs["Emission Strength"].default_value = emission
    return mat


def cube(name, xyz, dimensions, mat, bevel=0.0):
    mesh_key = (mat.name, dimensions, bevel)
    mesh = MESHES.get(mesh_key)
    if mesh is None:
        x, y, z = (axis / 2 for axis in dimensions)
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(
            [(-x, -y, -z), (x, -y, -z), (x, y, -z), (-x, y, -z),
             (-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)],
            [],
            [(3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4),
             (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)],
        )
        mesh.materials.append(mat)
        MESHES[mesh_key] = mesh
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = xyz
    if bevel:
        rounded = obj.modifiers.new("Soft worn edges", "BEVEL")
        rounded.width = bevel
        rounded.segments = 2
        obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return obj


def map_point(px, py, z=0):
    return ((px - MAP_WIDTH / 2) * UNIT, (MAP_HEIGHT / 2 - py) * UNIT, z)


def slab(name, px, py, width, height, bottom, depth, mat, bevel=0.0):
    return cube(name, map_point(px + width / 2, py + height / 2, bottom + depth / 2),
                (width * UNIT, height * UNIT, depth), mat, bevel)


def ornament(name, points, z, mat):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([map_point(x, y, z) for x, y in points], [], [tuple(reversed(range(len(points))))])
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)


def lozenge(x, y, width, height, z, mat):
    ornament("Inlaid diamond", [(x, y-height), (x+width, y), (x, y+height), (x-width, y)], z, mat)


def ellipsoid(name, xyz, axes, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, location=xyz)
    obj = bpy.context.object
    obj.name = name
    obj.scale = axes
    obj.data.materials.append(mat)
    for face in obj.data.polygons:
        face.use_smooth = True
    return obj


def stem(name, start, end, radius, mat):
    vector = Vector(end) - Vector(start)
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=12, radius=radius, depth=vector.length, location=(Vector(start) + Vector(end)) / 2
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = vector.to_track_quat("Z", "Y").to_euler()
    obj.data.materials.append(mat)
    return obj


def camera(xyz, target, width):
    lens = bpy.data.cameras.new("Orthographic camera")
    lens.type = "ORTHO"
    lens.ortho_scale = width
    obj = bpy.data.objects.new("Orthographic camera", lens)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = xyz
    if target is not None:
        obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = obj


def light(name, kind, xyz, energy, color, size, target=None):
    lamp = bpy.data.lights.new(name, kind)
    lamp.energy = energy
    lamp.color = color
    if kind == "AREA":
        lamp.size = size
    else:
        lamp.shadow_soft_size = size
    obj = bpy.data.objects.new(name, lamp)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = xyz
    if target is not None:
        obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def make_scene(name, width, height, transparent, samples):
    scene = bpy.data.scenes.new(name)
    bpy.context.window.scene = scene
    scene.world = bpy.data.worlds.new(name + " ambient")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.28, 0.22, 0.17, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.48
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    scene.render.film_transparent = transparent
    scene.view_settings.view_transform = "AgX"
    return scene


def carpet(x, y, w, h, weave, border, gold):
    slab("Woven rug", x, y, w, h, 0.012, 0.026, border, 0.008)
    slab("Dyed wool field", x + 3, y + 3, w - 6, h - 6, 0.038, 0.005, weave)
    for py in (y+6, y+h-7):
        slab("Brass-colored thread", x+5, py, w-10, 1.0, 0.044, 0.002, gold)
    for px in range(round(x + 14), round(x + w - 10), 23):
        lozenge(px, y + h / 2, 9, 10, 0.049, border)
        lozenge(px, y + h / 2, 6, 7, 0.050, weave)
        lozenge(px, y + h / 2, 2.5, 3, 0.051, gold)


def arch(x, y, width, height, z, mat):
    radius = width / 2
    rise = min(radius * 0.72, height * 0.72)
    points = []
    for i in range(17):
        angle = math.pi + i * math.pi / 16
        points.append((x + radius * math.cos(angle), y + rise + rise * math.sin(angle)))
    points += [(x + radius, y + height), (x - radius, y + height)]
    ornament("Recessed arch", points, z, mat)


def model_map():
    scene = make_scene("1978 hotel — playable floor", 1600, 1004, False, 12)
    camera((0, 0, 24), None, MAP_WIDTH * UNIT)
    plaster = material("Tawny lime plaster", "B68656")
    edge = material("Dark walnut border", "352720")
    wood = material("Walnut", "76492E")
    copper = material("Aged brass", "BA8A45", 0.48, 0.28)
    shadow = material("Recessed wood", "3D2A1F")
    gold = material("Inlay", "D4AC64")
    clay = material("Unglazed clay", "A36C48")
    tile_colors = [material("Hall tile " + str(i), shade) for i, shade in enumerate(
        ["876347", "AA8658", "AE895C", "BC9567", "9D754F", "B28A60"]
    )]
    floors = [
        [material(name + " " + str(i), shade) for i, shade in enumerate(colors)]
        for name, colors in [
            ("Red cedar", ["70482D", "8A5734", "845433", "966241", "795135"]),
            ("Olive plaster", ["594D35", "6C6441", "756542", "81764E", "6D5A40"]),
            ("Old parquet", ["69523B", "856541", "8B6847", "92724F", "795C3C"]),
        ]
    ]
    red = material("Burgundy wool", "783526")
    green = material("Olive wool", "495742")
    thread = material("Rug trim", "CEA269")
    window = material("Green night glass", "334940", 0.42)
    fabric = material("Ivory cotton", "E7CB98")
    pillow = material("Linen", "F5DFBD")
    blanket = material("Patterned rust blanket", "9B6145")
    glass = material("Amber lamp glass", "FFC874", 0.38, emission=0.18)
    leaves = material("Dusty olive leaves", "647047")
    deep_leaf = material("Leaf shadow", "414E35")
    rng = random.Random(1978)
    slab("Base of architectural model", 0, 0, MAP_WIDTH, MAP_HEIGHT, -0.19, 0.12, edge)
    for px, py, w, h in [(6, 6, 890, 5), (6, 555, 890, 5), (6, 8, 6, 550), (890, 8, 6, 550)]:
        slab("Mitered frame", px, py, w, h, -0.07, 0.10, wood, 0.014)
    for row in range(5):
        for column in range(43):
            x, y = 18 + column * 20, 215 + row * 26
            slab("Cement mosaic tile", x, y, 19.5, 25.5, -0.055, 0.055, rng.choice(tile_colors))
            lozenge(x + 10, y + 13, 5, 7, 0.006, edge if (row + column) % 2 else plaster)
    carpet(30, 282, 842, 40, red, thread, gold)
    for index in range(6):
        x, y = 21 + index % 3 * 293, 23 if index < 3 else 348
        slab("Guest room slab", x, y, 274, 190, -0.09, 0.08, shadow)
        palette = floors[index % 3]
        for row in range(9):
            start = x + 6
            intervals = [start] + [start + shift for shift in range(13 if row % 2 else 36, 262, 35)] + [x + 268]
            for left, right in zip(intervals, intervals[1:]):
                slab("Parquet board", left, y + 5 + row * 20, right - left - 0.7, 19.4,
                     -0.014, 0.014, rng.choice(palette))
        top_door = index >= 3
        for px, py, w, h in [(x, y + 2, 6, 186), (x + 268, y + 2, 6, 186)]:
            slab("Limewashed side wall", px, py, w, h, 0, 0.18, plaster, 0.024)
        for py, has_opening in [(y, top_door), (y + 183, not top_door)]:
            segments = [(x, 106), (x + 168, 106)] if has_opening else [(x, 274)]
            for left, width in segments:
                slab("Limewashed room partition", left, py, width, 7, 0, 0.32, plaster, 0.035)
                slab("Stained wood wall cap", left + 1, py + 2, width - 2, 3, 0.32, 0.025, wood)
        door_y = y if top_door else y + 190
        slab("Brass threshold", x + 108, door_y - 6, 58, 12, 0, 0.035, copper, 0.014)
        for offset in (106, 165):
            slab("Walnut jamb", x + offset, door_y - 7, 4, 14, 0.02, 0.26, wood, 0.015)
        if top_door:
            window_x, window_y = x + (73 if index % 2 else 201), y + 16
        else:
            window_x, window_y = x + 137, y + 13
        arch(window_x, window_y, 68, 37, 0.09, gold)
        arch(window_x, window_y + 3, 61, 32, 0.10, wood)
        arch(window_x, window_y + 7, 48, 25, 0.11, window)
        for bar in range(-18, 19, 9):
            slab("Mashrabiya lattice", window_x + bar, window_y + 16, 1.5, 16, 0.12, 0.02, copper)
            lozenge(window_x + bar + 0.6, window_y + 24, 3.4, 4, 0.145, gold)
        slab("Window sill", window_x - 36, window_y + 34, 72, 4, 0.04, 0.12, wood, 0.015)
        rug_x = x + (103 + (index % 3) * 5)
        carpet(rug_x, y + (110 if index < 3 else 61), 93, 54, red if index % 2 == 0 else green, thread, gold)
        # Bed coordinates match the station and collision rectangles in Godot.
        bx, by = x + 27, y + (76 if index < 3 else 137)
        slab("Walnut bed frame", bx, by, 88, 42, 0.02, 0.24, wood, 0.055)
        slab("Padded mattress", bx + 4, by + 3, 80, 36, 0.26, 0.12, fabric, 0.06)
        slab("Walnut headboard", bx - 3, by - 1, 6, 44, 0, 0.45, wood, 0.028)
        slab("Pillow", bx + 8, by + 8, 22, 23, 0.38, 0.11, pillow, 0.075)
        slab("Wool blanket", bx + 34, by + 4, 47, 34, 0.38, 0.065, blanket, 0.037)
        for offset in (41, 51, 61, 71):
            lozenge(bx + offset, by + 21, 3, 6, 0.448, fabric)
        for px in (bx + 33, bx + 77):
            slab("Blanket stitching", px, by + 6, 1, 29, 0.448, 0.002, gold)
        cx, cy = x + 208, y + (84 if index < 3 else 146)
        slab("Nightstand", cx, cy, 43, 23, 0, 0.40, wood, 0.045)
        slab("Drawer pull", cx + 17, cy + 19, 9, 2, 0.40, 0.036, copper, 0.008)
        slab("Bakélite radio", cx + 11, cy + 3, 23, 10, 0.40, 0.16, shadow, 0.021)
        slab("Radio grille", cx + 13, cy + 5, 18, 6, 0.56, 0.012, copper)
        for n in range(3):
            slab("Radio grille engraving", cx + 14, cy + 6 + n * 2, 12, 0.6, 0.573, 0.007, edge)
        for offset in (29, 244):
            lx, ly = x + offset, y + (35 if index < 3 else 44)
            slab("Brass lantern housing", lx - 6, ly - 6, 12, 12, 0.15, 0.30, copper, 0.03)
            slab("Amber glass top", lx - 4, ly - 4, 8, 8, 0.45, 0.05, glass, 0.03)
            light("Lantern pool", "POINT", map_point(lx, ly, 0.95), 15, (1, 0.66, 0.34), 0.21)
        plant(x + 249, y + (145 if index < 3 else 106), clay, leaves, deep_leaf)
    slab("Reception counter", 402, 246, 112, 32, 0, 0.68, wood, 0.075)
    slab("Counter brass edging", 404, 248, 108, 28, 0.68, 0.042, copper, 0.03)
    slab("Counter walnut top", 407, 250, 102, 23, 0.722, 0.025, wood)
    slab("Open guest ledger", 444, 252, 23, 13, 0.75, 0.03, fabric, 0.014)
    slab("Ledger crease", 455, 252, 1, 13, 0.78, 0.005, wood)
    ellipsoid("Brass call bell", map_point(485, 258, 0.82), (0.13, 0.13, 0.08), copper)
    slab("Rotary telephone", 415, 253, 17, 10, 0.75, 0.09, shadow, 0.035)
    ellipsoid("Telephone dial", map_point(423, 258, 0.85), (0.048, 0.048, 0.014), gold)
    for x, y in [(55, 242), (850, 242), (48, 333), (852, 333)]:
        plant(x, y, clay, leaves, deep_leaf)
    light("Warm ceiling bounce", "AREA", (-1.5, 1, 8), 1210, (1.0, 0.81, 0.62), 12, (0, 0, 0))
    light("Cool night spill", "AREA", (2, 5, 5), 260, (0.58, 0.72, 1.0), 7, (0, 2, 0))
    return scene


def plant(x, y, clay, leaves, shade):
    ellipsoid("Earthenware planter", map_point(x, y, 0.12), (0.16, 0.16, 0.14), clay)
    for i in range(6):
        angle = math.tau * i / 6
        leaf = ellipsoid("Leaf", map_point(x + 6 * math.cos(angle), y + 6 * math.sin(angle), 0.27 + 0.02 * (i % 2)),
                         (0.11, 0.045, 0.045), leaves if i % 2 == 0 else shade)
        leaf.rotation_euler.z = -angle


def worker(direction, phase, costume):
    cap, shirt, apron, skin, hair, shoes, broom = costume
    angle = direction * math.pi / 2
    turn = mathutils_rotate(angle)
    stride = 0.24 if phase else 0.0
    for sign in (-1, 1):
        x = sign * 0.19
        front = sign * stride
        stem("Trouser leg", turn(x, front * 0.25, 0.58), turn(x, front, 0.14), 0.12, shoes)
        ellipsoid("Leather shoe", turn(x, front - 0.07, 0.11), (0.145, 0.18, 0.09), shoes).rotation_euler.z = angle
        stem("Shirt sleeve", turn(sign * 0.34, 0, 1.17), turn(sign * 0.47, -front * 0.5, 0.83), 0.105, shirt)
        ellipsoid("Hand", turn(sign * 0.47, -front * 0.5, 0.80), (0.10, 0.096, 0.11), skin)
    ellipsoid("Burgundy work jacket", turn(0, 0, 0.95), (0.35, 0.25, 0.42), shirt).rotation_euler.z = angle
    cube("Cotton apron", turn(0, -0.24, 0.83), (0.45, 0.075, 0.48), apron, 0.025).rotation_euler.z = angle
    ellipsoid("Head", turn(0, -0.04, 1.53), (0.27, 0.245, 0.30), skin).rotation_euler.z = angle
    ellipsoid("Hair", turn(0, 0.1, 1.57), (0.26, 0.16, 0.23), hair).rotation_euler.z = angle
    ellipsoid("Brim of hotel cap", turn(0, -0.12, 1.75), (0.32, 0.26, 0.06), cap).rotation_euler.z = angle
    ellipsoid("Hotel cap", turn(0, 0, 1.81), (0.29, 0.23, 0.11), cap).rotation_euler.z = angle
    for x in (-0.090, 0.090):
        ellipsoid("Eye", turn(x, -0.263, 1.56), (0.026, 0.03, 0.026), hair)
    stem("Broom handle", turn(0.54, -0.10, 0.20), turn(0.48, -0.12, 1.42), 0.028, broom)
    cube("Broom head", turn(0.56, -0.10, 0.16), (0.28, 0.13, 0.20), broom, 0.018).rotation_euler.z = angle


def mathutils_rotate(angle):
    cosine, sine = math.cos(angle), math.sin(angle)

    def rotate(x, y, z):
        return (x * cosine - y * sine, x * sine + y * cosine, z)

    return rotate


def jinn():
    cloth = material("Jinn smoky olive cloth", "788472", 0.9)
    folds = material("Jinn fold shadows", "465748", 0.9)
    glow = material("Caramel eye light", "FFD78E", emission=0.8)
    ellipsoid("Floating head", (0, 0, 1.44), (0.48, 0.40, 0.50), cloth)
    ellipsoid("Shadowed face", (0, -0.29, 1.38), (0.32, 0.20, 0.36), folds)
    ellipsoid("Draped body", (0, 0.13, 0.90), (0.58, 0.33, 0.70), cloth)
    for offset, length in [(-0.34, 0.43), (0.0, 0.55), (0.32, 0.36)]:
        tail = ellipsoid("Trailing fold", (offset, 0.18, 0.46), (0.18, 0.19, length), cloth)
        tail.rotation_euler.y = -offset
    for x in (-0.14, 0.14):
        ellipsoid("Glowing eyes", (x, -0.467, 1.47), (0.061, 0.033, 0.041), glow)


def render(scene, path):
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True, scene=scene.name)


def join_sprites(paths, result):
    width = SPRITE * 4
    atlas = bpy.data.images.new("Worker animation atlas", width=width, height=SPRITE * 2, alpha=True)
    pixels = array("f", [0]) * (width * SPRITE * 2 * 4)
    for i, path in enumerate(paths):
        image = bpy.data.images.load(str(path), check_existing=False)
        sample = array("f", [0]) * (SPRITE * SPRITE * 4)
        image.pixels.foreach_get(sample)
        # Blender image rows start at the bottom, Godot's atlas rows at the top.
        x = (i % 4) * SPRITE
        y = (1 - i // 4) * SPRITE
        for row in range(SPRITE):
            start = ((y + row) * width + x) * 4
            pixels[start:start + SPRITE * 4] = sample[row * SPRITE * 4:(row + 1) * SPRITE * 4]
        bpy.data.images.remove(image)
    atlas.pixels.foreach_set(pixels)
    atlas.filepath_raw = str(result)
    atlas.file_format = "PNG"
    atlas.save()
    bpy.data.images.remove(atlas)


def make_cast(temp):
    costume = [
        material("Sand cap", "BD945C"), material("Burgundy uniform", "974637"),
        material("Ivory apron", "DEBC8F"), material("Skin", "C88E62"),
        material("Dark brown hair", "423024"), material("Leather shoes", "574130"),
        material("Broom straw and wood", "B78B52"),
    ]
    for phase in range(2):
        for direction in range(4):
            scene = make_scene(f"Worker — direction {direction}, pose {phase}", SPRITE, SPRITE, True, 10)
            worker(direction, phase, costume)
            camera((0, -4, 7.15), (0, 0, 0.86), 2.48)
            light("Worker key", "AREA", (-2, -3, 5), 330, (1.0, 0.81, 0.64), 3, (0, 0, 1))
            light("Worker fill", "AREA", (2, 1, 3), 110, (0.70, 0.85, 1), 2, (0, 0, 1))
            target = temp / f"worker-{direction}-{phase}.png"
            render(scene, target)
    join_sprites([temp / f"worker-{direction}-{phase}.png" for phase in range(2) for direction in range(4)], ASSETS / "worker.png")
    scene = make_scene("Jinn", SPRITE, SPRITE, True, 12)
    jinn()
    camera((0, -3.2, 5.2), (0, 0, 0.93), 2.7)
    light("Jinn key", "AREA", (-2, -3, 4), 260, (0.85, 1, 0.78), 3, (0, 0, 1))
    light("Jinn sheen", "AREA", (2, 1, 3), 155, (0.73, 0.87, 1), 2, (0, 0, 1))
    render(scene, ASSETS / "jinn.png")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    hotel = model_map()
    render(hotel, ASSETS / "hotel-floor.png")
    with tempfile.TemporaryDirectory() as temp:
        make_cast(Path(temp))
    for scene in bpy.data.scenes:
        scene.render.filepath = "//"
    hotel.render.filepath = "//../assets/hotel-floor.png"
    bpy.context.window.scene = hotel
    if bpy.context.screen:
        for area in bpy.context.screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.region_3d.view_perspective = "CAMERA"
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "art" / "siraj-hotel.blend"), compress=True)


if __name__ == "__main__":
    main()
