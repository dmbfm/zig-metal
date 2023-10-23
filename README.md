# zig-metal - Zig Bindings to the Metal API

This library is currently in alpha stage, don't use it in any serious projects!

Bindings are automatically generated using zig and libclang, but there are still
some issues with the code generation. The source code for the generator can be
found here: https://github.com/dmbfm/zig-metal-gen.

In the examples folder you can find a few samples which were directly
translated from apple's metal-cpp samples.

# Usage

Copy or clone `zig-metal` to a subdirectory of your project. For instance, if
you copy it to `libs/zig-metal` you should add this to your `build.zig`:

```zig 

const zig_metal = @import("libs/zig-metal/build.zig");

pub fn build(b: *std.Build) void {
    ...

    const zig_metal_pkg = zig_metal.package(b);
    zig_metal_pkg.link(exe);

    exe.linkFramework("Foundation");
    exe.linkFramework("Metal");
    exe.linkFramework("AppKit");    // If on macOS
    exe.linkFramework("MetalKit");  // If using MTKView
    ...
}

```

# What is included

All of the metal API and parts of the Foundation API which Metal depends on 
can are directly imported in the root zig-metal namespace, so you can access
them via `@import("zig-metal").MTLDevice, @import("zig-metal").NSString`, etc.

Additionally some basic AppKit bindings can be found in the `extras.appkit`
namespace, and basic MetalKit bindings in the `extras.metalkit` namespace.

# Examples

You can find some usage examples in the `examples` folder. These are
translations from Apple's samples for metal-cpp.

1. Window sample: `zig build run-window`

<img src="examples/01-window/screenshot.png" width="320">

2. Primitive sample: `zig build run-primitive`

<img src="examples/02-primitive/screenshot.png" width="320">

3. Argument Buffer sample: `zig build run-argbuffers`

<img src="examples/03-argbuffers/screenshot.png" width="320">

4. Animation sample: `zig build run-animation`

<img src="examples/04-animation/screenshot.png" width="320">

5. Instancing sample: `zig build run-instancing`

<img src="examples/05-instancing/screenshot.png" width="320">

6. Perspective sample: `zig build run-perspective`

<img src="examples/06-perspective/screenshot.png" width="320">

7. Lighting sample: `zig build run-lighting`

<img src="examples/07-lighting/screenshot.png" width="320">

8. Texturing sample: `zig build run-texturing`

<img src="examples/08-texturing/screenshot.png" width="320">

9. Compute sample: `zig build run-compute`

<img src="examples/09-compute/screenshot.png" width="320">

10. Compute to render sample: `zig build run-compute-to-render`

<img src="examples/10-compute_to_render/screenshot.png" width="320">


