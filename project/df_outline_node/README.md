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


#### Adding additional inputs
Adding additional input textures (buffers) requires separate SubViewports. In Forward+ mode, you can obtain depth or normals buffers by rendering the internal buffers to a Quadmesh in that SubViewport. However, compatibility mode does not have screen-space depth or normals buffers available. So, in order to use depth or normals -- or any other custom buffer for outlines -- you will need to apply a shader to every mesh in the scene that will render the required data to only a particular SubViewport. This is an advanced technique, and can be expensive.


#### Storage limitations
Compatibility mode provides very limited storage for transferring data *between* shader passes. We only have access to a single RGBA8 UNORM (in Forward+ with HDR enabled, you have a RGBA16 FLOAT). This means each channel can only store values [0-255] (normalized to [0.0-1.0]).

This is adequate for colors, but, to store screen coordinates for the jump flooding passes, the shaders divide the screen into a grid of 256 pixels. They store x and y in red and green, and the grid coordinates in blue. With CanvasLayers, only the RGB channels are useful, so this means we are already out of space! You may be able to revise this packing algorithm to squeeze a couple extra bools into the blue channel, but not much more than that.