### Distance Field Outlines: DFOutlineNode

See the main Distance Field Outlines [README](https://github.com/pink-arcana/godot-distance-field-outlines) for an overview of how DFOutlineNode works and its requirements.

#### Adding DFOutlineNode to your project
- Move the contents of the `df_outline_node` and `shared_dependencies` folders to your project.
- Update the paths to the shaders at the top of `df_outline_node.gd`.

#### Adding DFOutlineNode to your scene
- Right-click in your scene tree and select `Instantiate Child Scene...`. From the list, select `df_outline_node.tscn`.
- Select the newly-added DFOutlineNode to open its inspector.
- Under `Scene Camera`, assign your scene's Camera3D.
- Change the color and depth render layer assignments, if needed. See more on depth below.
- Change `Canvas Layer Start` to the CanvasLayer index you want DFOutlineNode to use. It will number each of its layers sequentially starting with that index. Depending on your screen size, this will be about 11-13 layers.
- Click on or create `DFOutlineSettings` to open the settings. (See [Settings](https://github.com/pink-arcana/godot-distance-field-outlines#settings) in the main README.)


### Previewing DFOutlineNode
There is no editor preview available. While DFOutlineNode is a `@tool` script, it won't create its post-processing layer stack in the editor.

However, when you run your project, you can view the layers in the Remote scene tree. To debug, you can hide or show different layers there. You can also view the passes in [RenderDoc](https://renderdoc.org/).


### Viewport troubleshooting
DFOutlineNode uses CanvasItem nodes to create its shader passes. This means that, unlike the 3D scene, any changes to viewport scaling in ProjectSettings can affect them. DFOutlineNode's [`_update_layers()` function](https://github.com/pink-arcana/godot-distance-field-outlines/blob/main/project/df_outline_node/df_outline_node.gd#L248) attempts to compensate for changes in viewport size and content scale. If you run into problems in your project, this is where you want to look at first.


#### Depth fade in DFOutlineNode
In Forward+, we can get the the depth buffer by putting it on a full-screen Quadmesh in a separate SubViewport. But DFOutlineNode is built for Compatibility mode. And Compatibility mode does not make a screenspace depth buffer available.

That means we need to create our own. This project comes with a Spatial shader that creates a linear depth buffer based on distance from the camera. It will only render to a specified depth layer. On any other layer, it will be transparent.

If you leave the `Assign depth materials` setting checked, DFOutlineNode will automatically assign this shader as a material to the `Material Overlay` slot for *every* MeshInstance3D in your scene.

If you prefer to assign the shader yourself or create your own depth buffer manually, uncheck `Assign depth materials`.

If you don't need depth fade at all, you can remove the logic from the DFOutlineNode script and remove the DepthSubViewport from its .tscn file. This will make it a little bit faster, too.


#### Adding additional buffers
In addition to depth, Compatibility mode also doesn't make screen-space normals or other buffers available. But the Spatial shader we are using to create a depth buffer has room to spare!

This means that you can edit the `spatial_depth_next_pass.gdshader` script to add other data you need and it will be almost free.

For example, if you want to use [fresnel](https://godotshaders.com/snippet/fresnel/) to find object edges for your outlines, you can put the math in the `fragment()` shader, output your value to the green channel (make sure it's normalized \[0.0-1.0\]), and then read it from `extraction.gdshader`.

The extraction shader doesn't use the depth buffer by default. So you will also need to add it as a uniform to `extraction.gdshader`, and assign the DepthSubViewport's texture to that uniform in `df_outline_node.gd`.


#### Storage limitations
As described above, adding additional input buffers is relatively simple, and not too expensive. But Compatibility mode does not give us enough storage to transfer additional data *between* shader passes. We only have access to a single RGBA8 UNORM (in Forward+ with HDR enabled, you have a RGBA16 FLOAT). This means each channel can only store values [0-255] (normalized to [0.0-1.0]).

To store screen coordinates for the jump flooding passes, the shaders divide the screen into a grid of 256 pixels. They store x and y in red and green, and the grid coordinates in blue. With CanvasLayers, only the RGB channels are useful, so this means we are already out of space! You should be able to revise this packing algorithm to squeeze a couple extra bools into the blue channel, but not much more than that.